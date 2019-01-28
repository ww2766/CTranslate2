FROM ubuntu:16.04 as builder

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        cpio \
        git \
        libboost-program-options-dev \
        python-dev \
        python-pip \
        wget && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /root

RUN wget https://cmake.org/files/v3.12/cmake-3.12.2-Linux-x86_64.tar.gz
RUN tar xf cmake-3.12.2-Linux-x86_64.tar.gz && \
    rm cmake-3.12.2-Linux-x86_64.tar.gz
ENV PATH=$PATH:/root/cmake-3.12.2-Linux-x86_64/bin

ENV MKL_VERSION=2019.2
COPY deps/l_mkl_${MKL_VERSION}.*.tgz .
RUN tar xf l_mkl_*.tgz && \
    cd l_mkl_* && \
    sed -i 's/ACCEPT_EULA=decline/ACCEPT_EULA=accept/g' silent.cfg && \
    sed -i 's/ARCH_SELECTED=ALL/ARCH_SELECTED=INTEL64/g' silent.cfg && \
    ./install.sh -s silent.cfg && \
    cd .. && \
    rm -r l_mkl_*

ENV MKLDNN_ROOT=/root/mkl-dnn
ENV MKLDNN_REVISION=7de193ce9a4f1a302a93d0d30bd9a940646ffd95
RUN git clone https://github.com/intel/mkl-dnn mkl-dnn-git && \
    cd mkl-dnn-git && \
    git checkout ${MKLDNN_REVISION} && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=${MKLDNN_ROOT} -DCMAKE_PREFIX_PATH=/opt/intel/lib/intel64 \
          -DARCH_OPT_FLAGS="" -DMKLDNN_THREADING=OMP:INTEL \
          -DWITH_TEST=OFF -DWITH_EXAMPLE=OFF .. && \
    make -j4 && make install && \
    cd ../.. && rm -r mkl-dnn-git

WORKDIR /root/ctranslate2-dev

COPY mkl_symbol_list .
COPY cli cli
COPY include include
COPY src src
COPY tests tests
COPY CMakeLists.txt .

ARG CXX_FLAGS
ENV CXX_FLAGS=${CXX_FLAGS}

RUN mkdir build && \
    cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=/root/ctranslate2 \
          -DCMAKE_PREFIX_PATH=${MKLDNN_ROOT} -DWITH_MKLDNN=ON \
          -DCMAKE_BUILD_TYPE=Release -D -DCMAKE_CXX_FLAGS="${CXX_FLAGS}" .. && \
    VERBOSE=1 make -j4 && \
    make install

COPY python python

WORKDIR /root/ctranslate2-dev/python
RUN pip --no-cache-dir install setuptools wheel pybind11
RUN CFLAGS="-DWITH_MKL=ON" CTRANSLATE2_ROOT=/root/ctranslate2 \
    python setup.py bdist_wheel

WORKDIR /root
RUN cp /opt/intel/lib/intel64/libiomp5.so /root/ctranslate2/lib && \
    cp -P /root/mkl-dnn/lib/libmkldnn.so* /root/ctranslate2/lib && \
    cp /root/ctranslate2-dev/python/dist/*whl /root/ctranslate2

FROM ubuntu:16.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libboost-program-options1.58.0 \
        python-pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /root/ctranslate2 /root/ctranslate2
RUN pip --no-cache-dir install /root/ctranslate2/*.whl

WORKDIR /root

ENV LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/root/ctranslate2/lib
