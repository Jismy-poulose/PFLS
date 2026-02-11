#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# 1️⃣ Define directories
# ---------------------------
BASE_DIR="/home/jismy/PFLS-DATA-PACKAGE/EXC-004"
RAW_DIR="$BASE_DIR/RAW-DATA"
COMBINED_DIR="$BASE_DIR/COMBINED-DATA"
TRANS_FILE="$RAW_DIR/sample-translation.txt"

mkdir -p "$COMBINED_DIR"
shopt -s nullglob

# ---------------------------
# 2️⃣ Load sample translation
# ---------------------------
declare -A SAMPLE_MAP
while read -r lib culture rest; do
    SAMPLE_MAP["$lib"]="$culture"
done < <(tail -n +2 "$TRANS_FILE")

echo "Loaded sample translations:"
for lib in "${!SAMPLE_MAP[@]}"; do
    echo "$lib -> ${SAMPLE_MAP[$lib]}"
done

# ---------------------------
# 3️⃣ Loop over DNA folders
# ---------------------------
for dir in "$RAW_DIR"/DNA*; do
    lib=$(basename "$dir")
    culture="${SAMPLE_MAP[$lib]}"

    [[ -z "$culture" ]] && { echo "Skipping $lib: no mapping"; continue; }
    echo "Processing $lib -> $culture"

    # Copy metadata
    cp "$dir/checkm.txt" "$COMBINED_DIR/${culture}-CHECKM.txt"
    cp "$dir/gtdb.gtdbtk.tax" "$COMBINED_DIR/${culture}-GTDB-TAX.txt"

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
    for fasta in "$bins_dir"/*.fasta; do
        [[ -e "$fasta" ]] || continue
        filename=$(basename "$fasta")

        # Handle unbinned
        if [[ "$filename" == *unbinned* ]]; then
            cp "$fasta" "$COMBINED_DIR/${culture}_UNBINNED.fa"
            echo "  Copied unbinned: $filename -> ${culture}_UNBINNED.fa"
            continue
        fi

        # Extract bin number
        bin_number=$(echo "$filename" | sed 's/bin-\([0-9]*\).fasta/\1/')

        # Get CheckM info
        check_line=$(awk -v b="$bin_number" '$1 ~ ("bin-"b"$") {print; exit}' "$dir/checkm.txt")
        if [[ -z "$check_line" ]]; then
            number=$(printf "%03d" "$bin_count")
            cp "$fasta" "$COMBINED_DIR/${culture}_BIN_${number}.fa"
            ((bin_count++))
            echo "  Copied missing CheckM: $filename -> ${culture}_BIN_${number}.fa"
            continue
        fi

        completion=$(echo "$check_line" | awk '{print $(NF-2)}')
        contamination=$(echo "$check_line" | awk '{print $(NF-1)}')

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
echo "Fixing all FASTA headers..."

for fasta in "$COMBINED_DIR"/*.fa "$COMBINED_DIR"/*.fasta; do
    [[ -f "$fasta" ]] || continue
    filename=$(basename "$fasta")

    # Extract culture
    culture="${filename%%_*}"

    # Extract type
    if [[ "$filename" =~ (MAG|BIN|UNBINNED) ]]; then
        type="${BASH_REMATCH[1]}"
    else
        type="UNKNOWN"
    fi

    # Extract bin number safely (decimal)
    if [[ "$filename" =~ ${type}_([0-9]{1,3}) ]]; then
        binnum=$(printf "%03d" $((10#${BASH_REMATCH[1]})))
    else
        binnum="001"
    fi

    tmpfile=$(mktemp)
    seq=1

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == ">"* ]]; then
            printf ">%s_%s_%s_%04d\n" "$culture" "$type" "$binnum" "$seq" >> "$tmpfile"
            ((seq++))
        else
            printf "%s\n" "$line" >> "$tmpfile"
        fi
    done < "$fasta"

    mv "$tmpfile" "$fasta"
    echo "  Headers fixed in $filename, total sequences: $seq"
done

echo "All FASTA headers are now standardized."
