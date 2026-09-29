FROM ubuntu:24.04
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    shellcheck sudo git openssh-client acl nginx php8.3-fpm php8.3-cli postgresql
WORKDIR /work
CMD ["bash", "tests/integration.sh"]
