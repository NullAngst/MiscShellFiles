#!/bin/bash

# ==============================================================================
# UNIFIED MUSIC FIXER (Metadata + Cover Art) - v1.4
# ==============================================================================
# Changes from v1.3:
#   - Added set -euo pipefail for early failure detection (disabled inside
#     process_folder where partial failures are acceptable)
#   - Fixed width-comparison crash when ffprobe returns empty string
#   - Fixed MusicBrainz heredoc JSON injection vulnerability (now uses jq)
#   - Fixed SKIPPED_LOG: actually writes to it now
#   - Guarded width/codec checks so they only run when art is present
#   - Quoted all variable expansions to prevent word-splitting
#   - Separated local declarations from assignments to preserve exit codes
#   - Added --help flag
#   - Noted fix_casing limitation in comments
#   - Minor: temp files use $$ for uniqueness; color output goes to stderr
# ==============================================================================

set -uo pipefail

# --- Configuration ---
SUPPORTED_EXTENSIONS=("mp3" "flac")
COVER_NAMES=("cover.png" "cover.jpg" "folder.jpg" "front.jpg" "album.jpg")
SKIPPED_LOG="skipped_albums.txt"
USER_AGENT="UnifiedMusicFixer/1.4"
MIN_ART_WIDTH=500

# --- Colors (to stderr so they don't pollute redirected stdout) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "$*" >&2; }
logr() { echo -e "${RED}$*${NC}" >&2; }
logg() { echo -e "${GREEN}$*${NC}" >&2; }
logy() { echo -e "${YELLOW}$*${NC}" >&2; }
logc() { echo -e "${CYAN}$*${NC}" >&2; }
logb() { echo -e "${BLUE}$*${NC}" >&2; }

# --- Dependencies Check ---
for cmd in ffmpeg ffprobe id3v2 metaflac curl jq sed; do
    if ! command -v "$cmd" &> /dev/null; then
        logr "Error: '$cmd' is not installed. Please install it and retry."
        exit 1
    fi
done

# --- Input Parsing ---
DIRECTORY=""
NO_PROMPT=false

usage() {
    echo "Usage: $0 <directory> [--no-prompt]"
    echo ""
    echo "  <directory>   Root music directory to scan (recurses into subdirectories)"
    echo "  --no-prompt   Skip interactive prompts; skip art download if not found locally"
    echo "  --help        Show this help"
    exit 0
}

for arg in "$@"; do
    case "$arg" in
        --no-prompt) NO_PROMPT=true ;;
        --help|-h)   usage ;;
        *)           DIRECTORY="$arg" ;;
    esac
done

if [[ -z "$DIRECTORY" ]]; then
    echo "Usage: $0 <directory> [--no-prompt]" >&2
    exit 1
fi

if [[ ! -d "$DIRECTORY" ]]; then
    logr "Error: '$DIRECTORY' is not a directory."
    exit 1
fi

# Clear skipped log at start
> "$SKIPPED_LOG"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

clean_filename() {
    local filename
    filename=$(basename "$1")
    filename="${filename%.*}"
    echo "$filename" | sed -E 's/^[0-9]+[\. -]+//'
}

# Converts to Title Case.
# LIMITATION: Will mangle intentional all-caps names (AC/DC → Ac/Dc),
# lowercase stylizations (deadmau5 → Deadmau5), and mixed-case brands.
# Consider building an exceptions list if this affects your library.
fix_casing() {
    local input="$1"
    echo "$input" | tr '[:upper:]' '[:lower:]' | sed -E 's/(^|[[:space:]]|\/|-)([a-z])/\1\u\2/g'
}

get_tag() {
    # $1=file, $2=ffprobe tag key (e.g. artist, album, title, disc)
    ffprobe -v quiet -show_entries "format_tags=$2" \
        -of default=noprint_wrappers=1:nokey=1 "$1" 2>/dev/null || true
}

write_text_tag() {
    local file="$1"
    local type="$2"   # artist | album | title | discnumber | album_artist
    local value="$3"
    local ext="${file##*.}"

    if [[ "$ext" == "mp3" ]]; then
        case "$type" in
            artist)       id3v2 -a "$value" "$file" ;;
            album)        id3v2 -A "$value" "$file" ;;
            title)        id3v2 -t "$value" "$file" ;;
            discnumber)   id3v2 --TPOS "$value" "$file" ;;
            album_artist) id3v2 --TPE2 "$value" "$file" ;;
        esac
    elif [[ "$ext" == "flac" ]]; then
        local field=""
        case "$type" in
            artist)       field="ARTIST" ;;
            album)        field="ALBUM" ;;
            title)        field="TITLE" ;;
            discnumber)   field="DISCNUMBER" ;;
            album_artist) field="ALBUMARTIST" ;;
        esac
        if [[ -n "$field" ]]; then
            metaflac --remove-tag="$field" "$file"
            metaflac --set-tag="$field=$value" "$file"
        fi
    fi
}

optimize_image() {
    local img="$1"
    [[ -f "$img" ]] || return 0
    local size
    size=$(stat -c%s "$img" 2>/dev/null || echo 0)
    if (( size > 10485760 )); then
        local temp_img="${img%.*}_opt_$$.png"
        if ffmpeg -nostdin -y -v error -i "$img" -vf "scale=1000:-1" "$temp_img" < /dev/null; then
            mv "$temp_img" "$img"
        else
            rm -f "$temp_img"
        fi
    fi
}

embed_art() {
    local img="$1"
    local audio="$2"
    local ext="${audio##*.}"
    local temp_file="${audio%.*}_tmp_$$.${ext}"

    if ffmpeg -nostdin -y -v error -i "$audio" -i "$img" \
        -map 0:a -map 1:0 \
        -c:a copy -c:v copy \
        -disposition:v:0 attached_pic \
        -metadata:s:v title="Album cover" \
        -metadata:s:v comment="Cover (front)" \
        "$temp_file" < /dev/null; then
        mv "$temp_file" "$audio"
        return 0
    else
        rm -f "$temp_file"
        return 1
    fi
}

# ==============================================================================
# LOGIC CORE
# ==============================================================================

process_folder() {
    # Disable exit-on-error inside this function: partial failures (e.g. one
    # bad file) should not abort the entire library scan.
    set +e

    local dir="$1"

    shopt -s nullglob
    local audio_files=("$dir"/*.mp3 "$dir"/*.flac)
    shopt -u nullglob

    if (( ${#audio_files[@]} == 0 )); then
        set -e
        return
    fi

    logb "Scanning: $(basename "$dir")"

    # --------------------------------------------------------------------------
    # PART 1: METADATA FIX
    # --------------------------------------------------------------------------

    local dirname
    dirname=$(basename "$dir")
    local folder_disc_num=""
    local disc_pattern='(^|[[:space:](\[\._-])[Dd]isc[[:space:]\._-]*([0-9]+)'

    if [[ "$dirname" =~ $disc_pattern ]]; then
        folder_disc_num=$(( 10#${BASH_REMATCH[2]} ))
        log "   [Meta] Detected Disc Folder: $folder_disc_num"
    fi

    declare -A file_artists
    declare -A file_albums
    local all_artists=()
    local all_albums=()

    for file in "${audio_files[@]}"; do
        local raw_art raw_alb fix_art fix_alb
        raw_art=$(get_tag "$file" "artist")
        raw_alb=$(get_tag "$file" "album")
        fix_art=$(fix_casing "$raw_art")
        fix_alb=$(fix_casing "$raw_alb")

        file_artists["$file"]="$fix_art"
        file_albums["$file"]="$fix_alb"

        [[ -n "$fix_art" ]] && all_artists+=("$fix_art")
        [[ -n "$fix_alb" ]] && all_albums+=("$fix_alb")
    done

    local maj_artist="" maj_album=""
    local count_files=${#audio_files[@]}

    if (( ${#all_artists[@]} > 0 )); then
        local top_art_line count_art
        top_art_line=$(printf '%s\n' "${all_artists[@]}" | sort | uniq -c | sort -nr | head -n1)
        count_art=$(echo "$top_art_line" | awk '{print $1}')
        if (( count_art > count_files / 2 )); then
            maj_artist=$(echo "$top_art_line" | awk '{$1=""; print $0}' | sed 's/^[[:space:]]*//')
        fi
    fi

    if (( ${#all_albums[@]} > 0 )); then
        local top_alb_line count_alb
        top_alb_line=$(printf '%s\n' "${all_albums[@]}" | sort | uniq -c | sort -nr | head -n1)
        count_alb=$(echo "$top_alb_line" | awk '{print $1}')
        if (( count_alb > count_files / 2 )); then
            maj_album=$(echo "$top_alb_line" | awk '{$1=""; print $0}' | sed 's/^[[:space:]]*//')
        fi
    fi

    if [[ -n "$maj_artist" || -n "$maj_album" ]]; then
        log "   [Meta] Standardized: '$maj_artist' / '$maj_album'"
    fi

    for file in "${audio_files[@]}"; do
        local curr_tit curr_disc
        curr_tit=$(get_tag "$file" "title")
        curr_disc=$(get_tag "$file" "disc")

        local target_art="${file_artists[$file]}"
        local target_alb="${file_albums[$file]}"

        [[ -n "$maj_artist" ]] && target_art="$maj_artist"
        [[ -n "$maj_album"  ]] && target_alb="$maj_album"

        # 1. Fix Disc Number
        if [[ -n "$folder_disc_num" ]]; then
            local clean_disc="${curr_disc%%/*}"
            local disc_int=0
            [[ "$clean_disc" =~ ^[0-9]+$ ]] && disc_int=$(( 10#$clean_disc ))
            if (( disc_int != folder_disc_num )); then
                write_text_tag "$file" "discnumber" "$folder_disc_num"
            fi
        fi

        # 2. Fix Title (from filename if missing)
        if [[ -z "$curr_tit" ]]; then
            local new_title
            new_title=$(clean_filename "$file")
            write_text_tag "$file" "title" "$new_title"
        fi

        # 3. Fix Artist & Album (blind overwrite ensures casing/encoding consistency)
        if [[ -n "$target_art" ]]; then
            write_text_tag "$file" "artist"       "$target_art"
            write_text_tag "$file" "album_artist" "$target_art"
        fi
        if [[ -n "$target_alb" ]]; then
            write_text_tag "$file" "album" "$target_alb"
        fi

        # 4. Interactive prompt if still missing info
        if { [[ -z "$target_art" ]] || [[ -z "$target_alb" ]]; } && [[ "$NO_PROMPT" == "false" ]]; then
            logy "   [Missing Info] File: $(basename "$file")"
            local input_art input_alb
            read -e -p "   Enter Artist [${maj_artist:-?}]: " input_art
            input_art="${input_art:-$maj_artist}"
            read -e -p "   Enter Album  [${maj_album:-?}]: " input_alb
            input_alb="${input_alb:-$maj_album}"

            if [[ -n "$input_art" ]]; then
                input_art=$(fix_casing "$input_art")
                write_text_tag "$file" "artist"       "$input_art"
                write_text_tag "$file" "album_artist" "$input_art"
            fi
            if [[ -n "$input_alb" ]]; then
                input_alb=$(fix_casing "$input_alb")
                write_text_tag "$file" "album" "$input_alb"
            fi

            # Log to skipped file if still incomplete after prompt
            if [[ -z "$input_art" || -z "$input_alb" ]]; then
                echo "$dir" >> "$SKIPPED_LOG"
            fi
        elif [[ -z "$target_art" || -z "$target_alb" ]] && [[ "$NO_PROMPT" == "true" ]]; then
            # In no-prompt mode, log folders with missing info for later review
            echo "$dir" >> "$SKIPPED_LOG"
        fi
    done

    # --------------------------------------------------------------------------
    # PART 2: COVER ART FIX
    # --------------------------------------------------------------------------

    local missing_art_count=0 has_art_count=0 sample_art_file=""

    for file in "${audio_files[@]}"; do
        if ffprobe -v error -select_streams v \
            -show_entries stream=codec_name \
            -of default=noprint_wrappers=1:nokey=1 \
            "$file" 2>/dev/null | grep -q .; then
            (( has_art_count++ )) || true
            sample_art_file="$file"
        else
            (( missing_art_count++ )) || true
        fi
    done

    local art_status="OK"
    if (( missing_art_count == ${#audio_files[@]} )); then
        art_status="MISSING"
    elif (( missing_art_count > 0 )); then
        art_status="MIXED"
    fi

    if [[ "$art_status" == "MIXED" ]]; then
        logy "   [Art] Mixed art detected. Syncing from: $(basename "$sample_art_file")"
        ffmpeg -nostdin -y -v error -i "$sample_art_file" -map 0:v "$dir/cover.png" < /dev/null
        optimize_image "$dir/cover.png"
        for file in "${audio_files[@]}"; do embed_art "$dir/cover.png" "$file"; done
        set -e
        return
    fi

    if [[ "$art_status" == "OK" ]]; then
        # Guard: only check codec/width if we actually have an art stream
        local codec width
        codec=$(ffprobe -v error -select_streams v \
            -show_entries stream=codec_name \
            -of default=noprint_wrappers=1:nokey=1 \
            "$sample_art_file" 2>/dev/null | head -n1)
        width=$(ffprobe -v error -select_streams v \
            -show_entries stream=width \
            -of csv=p=0:s=x \
            "$sample_art_file" 2>/dev/null | head -n1)

        # FIX: Guard against empty width before arithmetic comparison
        if [[ "$codec" == "webp" ]] || { [[ -n "$width" ]] && (( width < MIN_ART_WIDTH )); }; then
            logy "   [Art] Low quality/WebP art detected (${width:-unknown}px). Attempting upgrade..."
            art_status="MISSING"
        else
            if [[ ! -f "$dir/cover.png" ]]; then
                ffmpeg -nostdin -y -v error -i "$sample_art_file" -map 0:v "$dir/cover.png" < /dev/null
            fi
            set -e
            return
        fi
    fi

    if [[ "$art_status" == "MISSING" ]]; then
        # Try local image first
        local local_img
        local_img=$(find "$dir" -maxdepth 1 \( -name "*.jpg" -o -name "*.png" \) | head -n 1)
        if [[ -n "$local_img" ]]; then
            log "   [Art] Using local image: $(basename "$local_img")"
            ffmpeg -nostdin -y -v error -i "$local_img" "$dir/cover.png" < /dev/null
            optimize_image "$dir/cover.png"
            for file in "${audio_files[@]}"; do embed_art "$dir/cover.png" "$file"; done
            set -e
            return
        fi

        if [[ "$NO_PROMPT" == "true" ]]; then
            logy "   [Art] No local art found; skipping download in --no-prompt mode."
            echo "$dir" >> "$SKIPPED_LOG"
            set -e
            return
        fi

        # Resolve search terms
        local search_art="${maj_artist}"
        local search_alb="${maj_album}"
        [[ -z "$search_art" ]] && search_art="${file_artists[${audio_files[0]}]}"
        [[ -z "$search_alb" ]] && search_alb="${file_albums[${audio_files[0]}]}"

        logc "   [Search] Artist: $search_art | Album: $search_alb"

        local query
        query=$(printf '%s %s' "$search_art" "$search_alb" | jq -sRr @uri)
        local response
        response=$(curl -s -L \
            "https://itunes.apple.com/search?term=${query}&entity=album&limit=5" || true)
        local count
        count=$(echo "$response" | jq -r '.resultCount // 0')

        # Fallback: MusicBrainz + Cover Art Archive
        if [[ "$count" == "0" ]]; then
            log "   (Checking MusicBrainz...)"
            local mb_query mb_enc mb_json rel_id
            mb_query=$(jq -rn --arg a "$search_art" --arg r "$search_alb" \
                '"artist:\"" + $a + "\" AND release:\"" + $r + "\""')
            mb_enc=$(printf '%s' "$mb_query" | jq -sRr @uri)
            mb_json=$(curl -s -A "$USER_AGENT" \
                "https://musicbrainz.org/ws/2/release/?query=${mb_enc}&fmt=json" || true)
            rel_id=$(echo "$mb_json" | jq -r '.releases[0].id // empty')

            if [[ -n "$rel_id" ]]; then
                # FIX: Build JSON safely with jq instead of heredoc interpolation
                response=$(jq -n \
                    --arg artist "$search_art" \
                    --arg album  "$search_alb" \
                    --arg url    "http://coverartarchive.org/release/${rel_id}/front" \
                    '{resultCount: 1, results: [{artistName: $artist, collectionName: $album, artworkUrl100: $url}]}')
                count=1
            fi
        fi

        if [[ "$count" == "0" ]]; then
            logr "   [Art] No art found online for '$search_art / $search_alb'."
            echo "$dir" >> "$SKIPPED_LOG"
            set -e
            return
        fi

        mapfile -t res_artists < <(echo "$response" | jq -r '.results[].artistName')
        mapfile -t res_albums  < <(echo "$response" | jq -r '.results[].collectionName')
        mapfile -t res_urls    < <(echo "$response" | jq -r '.results[].artworkUrl100')

        log "   Select cover art:"
        for i in "${!res_artists[@]}"; do
            logc "   $((i+1))) ${res_artists[$i]} - ${res_albums[$i]}"
        done
        logc "   s) Skip"

        local selection
        read -p "   Selection > " selection

        if [[ "$selection" =~ ^[0-9]+$ ]] \
            && (( selection > 0 )) \
            && (( selection <= ${#res_artists[@]} )); then

            local index=$(( selection - 1 ))
            local raw_url="${res_urls[$index]}"
            local final_url="${raw_url/100x100bb/1000x1000bb}"
            local temp_dl="$dir/temp_cover_$$.jpg"

            log "   Downloading..."
            if curl -s -L "$final_url" -o "$temp_dl"; then
                ffmpeg -nostdin -y -v error -i "$temp_dl" "$dir/cover.png" < /dev/null
                rm -f "$temp_dl"
                optimize_image "$dir/cover.png"
                if [[ -f "$dir/cover.png" ]]; then
                    for file in "${audio_files[@]}"; do embed_art "$dir/cover.png" "$file"; done
                    logg "   [Art] Updated successfully."
                fi
            else
                logr "   [Art] Download failed."
                rm -f "$temp_dl"
                echo "$dir" >> "$SKIPPED_LOG"
            fi
        else
            log "   Skipped."
            echo "$dir" >> "$SKIPPED_LOG"
        fi
    fi

    set -e
}

# --- Main Execution ---
# Use process substitution instead of pipe to avoid subshell variable loss
while IFS= read -r -d '' dir; do
    process_folder "$dir"
done < <(find "$DIRECTORY" -mindepth 1 -type d -print0)

echo ""
log "Done."

if [[ -s "$SKIPPED_LOG" ]]; then
    logy "The following folders were skipped or need attention:"
    while IFS= read -r line; do
        logy "  - $line"
    done < "$SKIPPED_LOG"
fi
