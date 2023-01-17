FROM ubuntu:16.04

ENV PATH="/usr/local/anaconda/bin:$PATH"

RUN apt-get update \
    && apt-get install -y eatmydata \
    && eatmydata apt-get install -y wget bzip2 \
      ca-certificates libglib2.0-0 libxext6 libsm6 libxrender1 \
      git \
    && apt-get clean

RUN wget https://repo.continuum.io/miniconda/Miniconda2-4.3.14-Linux-x86_64.sh \
            -O ~/anaconda.sh && \
         bash ~/anaconda.sh -b -p /usr/local/anaconda && \
         rm ~/anaconda.sh

RUN pip install markupsafe
RUN pip install Flask
RUN	conda config --add channels r
RUN	conda config --add channels bioconda
RUN	conda install -c kbchoi emase
RUN conda install -c kbchoi gbrs
RUN cd / git clone https://github.com/churchill-lab/alntools && cd alntools && python setup.py install
RUN conda install bowtie
RUN conda install bowtie2
RUN cd / && git clone https://github.com/churchill-lab/gbrs.git --branch release/0.1.6 && cd gbrs && python setup.py install
RUN cd / && git clone https://github.com/churchill-lab/emase-zero.git && cd emase-zero/src && make 