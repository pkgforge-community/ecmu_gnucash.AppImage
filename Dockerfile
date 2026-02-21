# Dockerfile pour compiler GnuCash et créer une AppImage
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Installer Python 3.13 depuis deadsnakes (runtime et dev)
RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && \
    apt-get install -y python3.13 libpython3.13 python3.13-dev libpython3.13-dev

#définir Python 3.13 comme version par défaut
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.13 2

# Installation des dépendances de compilation
RUN apt-get update && apt-get install -y \
    git wget sudo cmake make g++ pkg-config \
    libglib2.0-dev \
    libxml2-dev \
    libxslt1-dev \
    xsltproc \
    libgtk-3-dev \
    libwebkit2gtk-4.0-dev \
    libboost-all-dev \
    libicu-dev \
    swig \
    guile-3.0 \
    guile-3.0-dev \
    guile-3.0-libs \
    libgc1 \
    libgmp10 \
    libunistring2 \
    libffi8 \
    libdbi-dev libdbd-sqlite3 \
    libgwengui-gtk3-dev \
    libaqbanking-dev libofx-dev \
    gettext \
    intltool \
    googletest libgtest-dev libgmock-dev \
    file \
    patchelf \
    desktop-file-utils \
    zsync \
    && rm -rf /var/lib/apt/lists/*

# Créer l'utilisateur docker (uid = 1000 logiquement) avec droits sudo sans mot de passe, et l'utiliser en connexion par défaut
RUN useradd -m -s /bin/bash -G sudo docker \
    && echo "docker ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
USER docker

WORKDIR /workspace

# Point d'entrée par défaut
CMD ["/workspace/build-gnucash.sh"]
