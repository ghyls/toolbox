for f in logs/*.log; do
  awk '/Average throughput:/{printf "'$f' %.0f\n",$3}' "$f"
done
