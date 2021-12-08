FROM ubuntu:focal as base

# Warning: This file is experimental.

# Install system requirements
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install --yes \
    # Global requirements
    build-essential \
    curl \
    # If we don't need gcc, we should remove it.
    g++ \
    gcc \
    git \
    git-core \
    language-pack-en \
    libfreetype6-dev \
    libmysqlclient-dev \
    libssl-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libxslt1-dev \
    swig \
    # openedx requirements
    gettext \
    gfortran \
    graphviz \
    libffi-dev \
    libfreetype6-dev \
    libgeos-dev \
    libgraphviz-dev \
    libjpeg8-dev \
    liblapack-dev \
    libpng-dev \
    libsqlite3-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libxslt1-dev \
    # lynx: Required by https://github.com/edx/edx-platform/blob/b489a4ecb122/openedx/core/lib/html_to_text.py#L16
    lynx \
    ntp \
    pkg-config \
    python3-dev \
    python3-venv
RUN rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Define and switch to working directory.
WORKDIR /edx/app/edxapp/edx-platform

# Define environment variables.
ENV PATH /edx/app/edxapp/nodeenv/bin:${PATH}
ENV PATH ./node_modules/.bin:${PATH}
ENV PATH /edx/app/edxapp/edx-platform/bin:${PATH}
ENV CONFIG_ROOT /edx/etc/
ENV LMS_CFG /etc/etc/lms.yml
ENV STUDIO_CFG /etc/etc/studio.yml
ENV SETTINGS production

# Set up and activate (via direct PATH modification) a Python virtual environment.
ENV VIRTUAL_ENV=/edx/app/edxapp/venvs/edxapp
RUN python3.8 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# Copy `devstack.yml`s to locations specified in LMS_CFG and STUDIO_CFG.
RUN mkdir -p /edx/etc/
COPY cms/envs/devstack.yml /edx/etc/studio.yml
COPY lms/envs/devstack.yml /edx/etc/lms.yml

# Copy over the code.
# Although it would be more cache-friendly to copy over code *after*
# installing requirements (because code changes more often than requirements),
# we must copy it *before* installing requirements because ./requirements/edx/base.txt
# includes repository-local Python projects such as ./common/lib/xmodule.
# There exists a backlog item <https://openedx.atlassian.net/browse/BOM-2579>
# to dissolve those local projects, but until then, we must copy the code in first.
COPY . .

# Install Python and Node requirements.
# Python must be installed first because we install nodeenv via pip.
RUN pip install -r requirements/pip.txt
RUN pip install -r requirements/edx/base.txt
RUN nodeenv /edx/app/edxapp/nodeenv --node=12.11.1 --prebuilt
RUN npm set progress=false && npm install

# Make logging dir for paver.
RUN mkdir -p test_root/log

# Define lms target.
FROM base as lms
ENV SERVICE_VARIANT lms
# TODO: This compiles static assets.
# However, it's a bit of a hack, it's slow, and it's inefficient because makes the final Docker cache layer very large.
# We ought to be able to this higher up in the Dockerfile, and do it the same for Prod and Devstack.
RUN NO_PREREQ_INSTALL=1 paver update_assets lms --settings production
ENV DJANGO_SETTINGS_MODULE lms.envs.production
EXPOSE 8000
CMD gunicorn \
    -c /edx/app/edxapp/edx-platform/lms/docker_lms_gunicorn.py \
    --name lms \
    --bind=0.0.0.0:8000 \
    --max-requests=1000 \
    --access-logfile \
    - lms.wsgi:application

# Define studio target.
FROM base as studio
ENV SERVICE_VARIANT cms
# TODO: This compiles static assets.
# However, it's a bit of a hack, it's slow, and it's inefficient because makes the final Docker cache layer very large.
# We ought to be able to this higher up in the Dockerfile, and do it the same for Prod and Devstack.
RUN NO_PREREQ_INSTALL=1 paver update_assets cms --settings production
ENV DJANGO_SETTINGS_MODULE cms.envs.production
EXPOSE 8010
CMD gunicorn \
    -c /edx/app/edxapp/edx-platform/cms/docker_cms_gunicorn.py \
    --name cms \
    --bind=0.0.0.0:8010 \
    --max-requests=1000 \
    --access-logfile \
    - cms.wsgi:application
