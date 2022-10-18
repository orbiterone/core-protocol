FROM node:13.8.0

RUN wget https://github.com/ethereum/solidity/releases/download/v0.8.10/solc-static-linux -O /bin/solc && chmod +x /bin/solc

WORKDIR /var/www/orbiter

CMD ["/bin/bash"]
