FROM ubuntu:24.04
ARG NAME
ARG VERSION
ENV NAME=$NAME VERSION=$VERSION
LABEL module=$NAME version=$VERSION
CMD ["bash","-c","echo \"$NAME $VERSION target=$TARGET_NAME ip=$TARGET_IP\"; exec sleep infinity"]
