FROM ubuntu

RUN apt update && apt install git python3 python3-pip jq curl git git-lfs -y && \
  echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config

ADD *.sh /
ADD hub-mirror /hub-mirror
ADD hub-mirror-shell /hub-mirror-shell
ADD action.yml /

ENTRYPOINT ["/entrypoint.sh"]
