# ARG BASE_IMAGE=multiarch/debian-debootstrap:bullseye
ARG BASE_IMAGE=debian:bullseye
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get -y update && \
    apt-get -y install --no-install-recommends \
        git vim parted \
        quilt coreutils qemu-user-static debootstrap zerofree zip dosfstools \
        libarchive-tools libcap2-bin rsync grep udev xz-utils curl xxd file kmod bc \
        binfmt-support ca-certificates fdisk gpg pigz arch-test \
        openssh-client apt-utils binfmt-support \
    && rm -rf /var/lib/apt/lists/*

# Set up binfmt-support
# RUN update-binfmts --enable
# Set up SSH configuration
RUN mkdir -p /root/.ssh && \
chmod 700 /root/.ssh && \
ssh-keyscan -t rsa github.com >> /root/.ssh/known_hosts

COPY . /pi-gen/

VOLUME [ "/pi-gen/work", "/pi-gen/deploy"]
