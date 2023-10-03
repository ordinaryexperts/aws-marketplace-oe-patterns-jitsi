FROM ubuntu:22.04

ENV IN_DOCKER=true

COPY ubuntu_2204_appinstall.sh /tmp/ubuntu_2204_appinstall.sh
RUN bash /tmp/ubuntu_2204_appinstall.sh
RUN rm -f /tmp/ubuntu_2204_appinstall.sh
