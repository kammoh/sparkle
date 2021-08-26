FROM hdlc/sim:osvb

# RUN apt update && apt install -y software-properties-common
# RUN add-apt-repository ppa:deadsnakes/ppa
RUN apt update && apt install -y python3
# RUN mv /usr/bin/python3 /usr/bin/python3.7 && ln -sf /usr/bin/python3.9 /usr/bin/python3
RUN pip3 install --upgrade cffi