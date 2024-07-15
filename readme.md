# Pull-based deployments
default values for the variables:

UPDATE_PERIOD=60

IMAGE_FILTER="127\.0\.0\.1:5000" # regexp

DOCKER_HOSTS=unix:///var/run/docker.sock

TELEGRAM_BOT_TOKEN

TELEGRAM_CHAT_ID


## Docker Hub Image
https://hub.docker.com/r/dtorry/registry_listener


# Another service like this: 
An overview of various services that enable pull-based deployments, similar to the registry_listener:

## shepherd
A self-hosted service that watches for changes in a Git repository and automatically updates Docker containers.

https://github.com/djmaze/shepherd


## dockupdater
A tool that automatically updates Docker containers when a new image is available.

https://www.dockupdater.dev/


## watchtower
A container that monitors running Docker containers and automatically updates them when a new image is available.

https://www.ctl.io/developers/blog/post/watchtower-automatic-updates-for-docker-containers/

https://github.com/containrrr/watchtower

https://containrrr.dev/watchtower/


