for file in *.tr; do
  ~/bin/trill "$file" ../stdlib/*.tr
done
find . -d 1 -type f -not -name "*.tr" -not -name "*.sh" -exec rm {} \;
