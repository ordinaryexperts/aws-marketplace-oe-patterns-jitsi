FROM ubuntu:18.04

ENV IN_DOCKER=true
COPY setup.sh /tmp/setup.sh
COPY boot-kernel.sh /tmp/boot-kernel.sh
RUN bash /tmp/setup.sh
RUN rm -f /tmp/setup.sh
RUN rm -f /tmp/boot-kernel.sh