FASTA=$1
START=$(head -n1 $FASTA| awk '{print substr($1,1,1)}')
num_seq=$(grep '>' $FASTA|wc -l|awk '{print $1}')
total_length_of_seq=$(grep -v '>' $FASTA|awk 'BEGIN{total_length_of_seq=0}{total_length_of_seq += gsub(/[ATGCU]/, "", $1)} END {print total_length_of_seq}')
len_long_seq=$((grep ">" $FASTA) | awk 'BEGIN{FS=";"} {print $6}' | awk 'BEGIN{FS=":"} {print $2}' | sort -n | tail -n1)
len_short_seq=$((grep ">" $FASTA) | awk 'BEGIN{FS=";"} {print $6}' | awk 'BEGIN{FS=":"} {print $2}' | sort -n | head -n1)
avg_seq_len=$((total_length_of_seq/num_seq))
gc=$(grep -v '>' $FASTA|awk '{gc_count += gsub(/[GgCc]/, "", $1)} END {print gc_count}')
gc_cont=$(($gc*100/$total_length_of_seq))
if [ "$START" == '>' ] ; then
  echo "FASTA File Statistics:"
  echo "----------------------"
  else 
  echo "This is not a FASTA file" 
fi
 echo "Number of sequences:$num_seq"  
 echo "Total length of sequences: $total_length_of_seq"
if [ "$len_long_seq" -gt '0'&& "$len_short_seq" -gt '0'] ; then
  echo "Length of the longest sequence: $len_long_seq"
  echo "Length of the shortest sequence: $len_short_seq"
else
  echo "Length of the longest sequence:0"
  echo "Length of the shortest sequence:0"
fi
  
  echo "Average sequence length: $avg_seq_len"
  echo "GC Content (%): $gc_cont"
