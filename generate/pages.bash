path='../output'
for file in ${path}/*.png; do
  filename=$(basename "$file" .png)
  convert "$file" -crop 100%x20% -resize 450x172 -background none  -gravity center -extent 450x172 +repage +adjoin "${path}/tmp/${filename}.%d.png"
done

for file in ${path}/tmp/*.png; do
  if [ $(stat -f %z "$file") -gt 1024 ]; then
    filename=$(basename "$file" .png)
    delimiter="."
    n1="${filename%%${delimiter}*}"
    n2="${filename#*${delimiter}}"

    ffmpeg -y -i "$file" -filter_complex "drawtext=fontfile=ConcertOne-Regular.ttf:text='${n1} - ${n2}':fontcolor=black:fontsize=12:x=220:y=162" -pix_fmt rgba "${path}/out/p${filename}.png" 
  fi
done

for file in ${path}/out/*.png; do
  convert "$file"  -rotate 90 -flatten -unsharp 0x1 -type GrayScale -depth 2 "$file" 
  zopflipng -y -m --iterations=50 --filters=0me --lossy_8bit --lossy_transparent "$file" "$file"
done

rm -r ${path}/tmp/*