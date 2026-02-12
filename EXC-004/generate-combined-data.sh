#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# 1️⃣ Set directories
# ---------------------------
# Base directory can be passed as first argument, defaults to current directory
BASE_DIR="${1:-.}"
RAW_DIR="$BASE_DIR/RAW-DATA"
COMBINED_DIR="$BASE_DIR/COMBINED-DATA"
TRANS_FILE="$RAW_DIR/sample-translation.txt"

mkdir -p "$COMBINED_DIR"
shopt -s nullglob

# ---------------------------
# 2️⃣ Load sample translation
# ---------------------------
declare -A SAMPLE_MAP
if [[ -f "$TRANS_FILE" ]]; then
    while IFS=$'\t' read -r lib culture _rest; do
        SAMPLE_MAP["$lib"]="$culture"
    done < <(tail -n +2 "$TRANS_FILE")
else
    echo "[!] Translation file not found: $TRANS_FILE"
    exit 1
fi

echo "Loaded sample translations:"
for lib in "${!SAMPLE_MAP[@]}"; do
    echo "  $lib -> ${SAMPLE_MAP[$lib]}"
done

# ---------------------------
# 3️⃣ Loop over DNA folders
# ---------------------------
for dir in "$RAW_DIR"/DNA*; do
    [[ -d "$dir" ]] || continue
    lib=$(basename "$dir")
    culture="${SAMPLE_MAP[$lib]:-}"

    if [[ -z "$culture" ]]; then
        echo "Skipping $lib: no mapping"
        continue
    fi

    echo "Processing $lib -> $culture"

    # Copy metadata
    [[ -f "$dir/checkm.txt" ]] && cp "$dir/checkm.txt" "$COMBINED_DIR/${culture}-CHECKM.txt"
    [[ -f "$dir/gtdb.gtdbtk.tax" ]] && cp "$dir/gtdb.gtdbtk.tax" "$COMBINED_DIR/${culture}-GTDB-TAX.txt"

    bins_dir="$dir/bins"
    if [[ ! -d "$bins_dir" ]]; then
        echo "  Warning: no bins folder in $dir"
        continue
    fi

    mag_count=1
    bin_count=1

    # ---------------------------
    # 4️⃣ Copy and rename FASTAs
    # ---------------------------
    for fasta in "$bins_dir"/*.fasta "$bins_dir"/*.fa; do
        [[ -f "$fasta" ]] || continue
        filename=$(basename "$fasta")

        # Handle unbinned
        if [[ "$filename" =~ [Uu][Nn][Bb][Ii][Nn][Nn][Ee][Dd] ]]; then
            cp "$fasta" "$COMBINED_DIR/${culture}_UNBINNED.fa"
            echo "  Copied unbinned: $filename -> ${culture}_UNBINNED.fa"
            continue
        fi

        # Extract bin number from filename
        if [[ "$filename" =~ bin[-_]?([0-9]+) ]]; then
            raw_bin="${BASH_REMATCH[1]}"
        else
            raw_bin="$bin_count"
        fi

        # Get CheckM info if available
        completion=0
        contamination=100
        if [[ -f "$dir/checkm.txt" ]]; then
            check_line=$(awk -v b="$raw_bin" '$1 ~ ("bin-"b"$") {print; exit}' "$dir/checkm.txt")
            if [[ -n "$check_line" ]]; then
                completion=$(echo "$check_line" | awk '{print $(NF-2)}')
                contamination=$(echo "$check_line" | awk '{print $(NF-1)}')
            fi
        fi

        # Decide MAG or BIN
        if (( $(echo "$completion >= 50" | bc -l) )) && (( $(echo "$contamination <= 5" | bc -l) )); then
            label="MAG"
            number=$(printf "%03d" "$mag_count")
            ((mag_count++))
        else
            label="BIN"
            number=$(printf "%03d" "$bin_count")
            ((bin_count++))
        fi

        cp "$fasta" "$COMBINED_DIR/${culture}_${label}_${number}.fa"
        echo "  Copied $filename -> ${culture}_${label}_${number}.fa"
    done
done

# ---------------------------
# 5️⃣ Fix FASTA headers
# ---------------------------
echo "Fixing FASTA headers..."
for fasta in "$COMBINED_DIR"/*.fa "$COMBINED_DIR"/*.fasta; do
    [[ -f "$fasta" ]] || continue
    filename=$(basename "$fasta")

    # Extract info
    culture="${filename%%_*}"
    type=$(echo "$filename" | grep -oP '(MAG|BIN|UNBINNED)')
    binnum=$(echo "$filename" | grep -oP '(MAG|BIN)_[0-9]{3}' | cut -d'_' -f2 || echo "000")

    seq=1
    tmpfile=$(mktemp)

    awk -v prefix="$culture" -v type="$type" -v bin="$binnum" -v seq_start="$seq" '
    BEGIN { RS=">"; ORS="" }
    NR>1 {
        n = split($0, lines, "\n")
        printf ">" prefix "_" type "_" bin "_" "%04d\n", seq_start
        seq_start++
        for(i=2;i<=n;i++) if(lines[i] ~ /[A-Za-z]/) print lines[i] "\n"
    }' "$fasta" > "$tmpfile"

    mv "$tmpfile" "$fasta"
    echo "  Headers fixed in $filename"
done

echo "✅ All FASTA headers standardized. Combined data is in $COMBINED_DIR"
