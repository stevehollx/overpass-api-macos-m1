# Overpass API for Mac Silicon

The overpass API distributions from drolbr and wiktorn don't work with Docker Desktop on Apple Silicon Macs.

This project compiles and hosts a local Open Street Maps overpass API from OSMS source on a ubuntu docker image that will work for M1+ macs.

It handles permissions and socket files differently, which are where Docker Desktop and MacOS fight those other distribution methods.

This may also work on other platforms, but is untested. I am using this to host a local API for my other project ####### to query highways, so I trim the planet file down to just north_america highways with `osmium cat input.osm.pbf -o output.osm.bz2 --tag-filter w/highway`.

## Installation

1. Clone this project with `git clone <url>` to a folder. If using with my climb-analyzer project, you can put this in an `./overpass-api` folder within `/climb-analyzer`
2. Create `./db/` and `./cache/` folders and set permissions on `./cache` and `./db` folders to 755.
3. Fetch your region's OSM planet file from [geofabrik.de](https://download.geofabrik.de).
4. overpass-api expects a bz2 compression, and geofabrik hosts pbf format, so compress the file with: `osmium cat <input>.osm.pbf -o <output>.osm.bz2`
5. Edit the docker-compose.yml volume to reference the planet file you downloaded.
6. Watch the status of the planet file parsing and db building with `docker-compose logs -f --timestamps overpass-api`. Look for errors. You will see 'Reading XML file' if it is parsing properly. North America take 3-6 hours to load, Europe 6-12, and around 40 hours for the entire planet. After initializing once, the files will persist to the mounted ./db folder.

## Validation and using the API

1. Run ./tests.py to ensure the API is functioning properly.
