ARG IMAGE
#FROM
FROM $IMAGE

USER root
ENTRYPOINT [ "/bin/bash" ]

COPY conf/install-go.sh /tmp

RUN /tmp/install-go.sh