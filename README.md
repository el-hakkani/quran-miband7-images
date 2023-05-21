# The Noble Quran Page Image Generator for [miband7](https://github.com/el-hakkani/quran-miband7)

### Preparation

* Install Docker & Docker compose `https://docs.docker.com/engine/install`
* Install imagemagick `brew install imagemagick`
* Install ffmpeg `brew install ffmpeg`
* Install zopflipng `brew install zopfli`

### Build

* `docker-compose up -d`
* `docker-compose run gen /app/script/generate.pl --pages 1..604 --output ./output/`
* `cd generate && ./pages.bash`

> You can find compiled versions [here](https://github.com/el-hakkani/quran-miband7/tree/master/assets/pages)