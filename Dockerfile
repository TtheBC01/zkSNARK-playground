FROM rust:latest

RUN apt update \
    && apt install git \
                   curl \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt install -y nodejs \
    && npm install --global yarn

WORKDIR /root

RUN git clone https://github.com/iden3/circom.git

WORKDIR /root/circom

RUN cargo build --release \
    && cargo install --path circom \
    && npm install -g snarkjs

WORKDIR /root