FROM ubuntu:latest
RUN apt update -y
RUN apt install curl git sudo xz-utils -y

# Create a non-root user
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME \
    && mkdir /run/postgresql \
    && chown -R $USER_UID:$USER_GID /run/postgresql

# Install Nix

RUN mkdir -p /etc/nix && \
  mkdir -p /nix && chown $USERNAME /nix && \
  echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf

USER $USERNAME

RUN curl -L https://nixos.org/nix/install -o /nix/install-nix && \
    chmod a+x /nix/install-nix && \
    /nix/install-nix --no-daemon --no-channel-add && \
    rm /nix/install-nix

ENV PATH="$PATH:/home/dev/.nix-profile/bin:/home/dev/.nix-profile/bin/nix"

# Prebuild development environment

RUN mkdir -p /home/dev/workdir && chown -R $USERNAME /home/dev/workdir
WORKDIR /home/dev/workdir
COPY *.nix .
COPY *.lock .
COPY nix nix
RUN nix develop -c true

ENTRYPOINT ["nix", "develop"]
