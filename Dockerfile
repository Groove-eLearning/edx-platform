FROM ubuntu:focal as pre_base

# Warning: This file is experimental.
#
# Short-term goals:
# * Be a suitable replacement for the `edxops/edxapp` image in devstack (in progress).
# * Take advantage of Docker caching layers: aim to put commands in order of
#   increasing cache-busting frequency.
# * Related to ^, use no Ansible or Paver.
# Long-term goals:
# * Be a suitable base for production LMS and Studio images (THIS IS NOT YET THE CASE!).
#
# TODO: factor out an env-agnostic base from which a `dev` and `prod` stages
#       can be derived (for both lms and studio).

# Install system requirements.
# We update, upgrade, and delete lists all in one layer
# in order to reduce total image size.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install --yes \
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
        python3-venv && \
    rm -rf /var/lib/apt/lists/*

# Set locale.
RUN locale-gen en_US.UTF-8

# Define and switch to working directory.
WORKDIR /edx/app/edxapp/edx-platform

# Settings: locale
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Settings: configuration
ENV CONFIG_ROOT /edx/etc/
ENV LMS_CFG /edx/etc/lms.yml
ENV STUDIO_CFG /edx/etc/studio.yml
ENV EDX_PLATFORM_SETTINGS devstack_docker

# Settings: path
ENV VIRTUAL_ENV=/edx/app/edxapp/venvs/edxapp
ENV PATH=$VIRTUAL_ENV/bin:$PATH
ENV PATH ./node_modules/.bin:${PATH}
ENV PATH /edx/app/edxapp/edx-platform/bin:${PATH}
ENV PATH /edx/app/edxapp/nodeenv/bin:${PATH}

# Settings: paver
# We intentionally don't use paver in this Dockerfile, but Devstack may invoke paver commands
# during provisioning. Enabling NO_PREREQ_INSTALL tells paver not to re-install Python
# requirements for every paver command, saving a lot of time.
ENV NO_PREREQ_INSTALL=1

# Copy in supporting files from expected in '/edx' directory.
COPY docker/edx /edx

# Dump above environment vars to ../edxapp_env so they can be available to
# those opening a shell against this container.
RUN (echo "export LANG='$LANG'" \
  && echo "export PATH='$PATH'" \
  && echo "export LMS_CFG='$LMS_CFG'" \
  && echo "export STUDIO_CFG='$STUDIO_CFG'" \
  && echo "export EDX_PLATFORM_SETTINGS='$EDX_PLATFORM_SETTINGS'" \
  && echo "export NO_PREREQ_INSTALL='$NO_PREREQ_INSTALL'" \
    ) >> ../edxapp_env

# Set up a Python virtual environment.
# It is already 'activated' because $VIRTUAL_ENV/bin was put on $PATH.
RUN python3.8 -m venv $VIRTUAL_ENV

FROM pre_base AS base

# Install Python requirements.
# Requires copying over requirements files, but not entire repository.
# We filter out the local ('common/*' and 'openedx/*', and '.') Python projects,
# because those require code in order to be installed. They will be installed
# later. This step can be simplified when the local projects are dissolved
# (see https://openedx.atlassian.net/browse/BOM-2579).
COPY requirements requirements
RUN  sed '/^-e \(common\/\|openedx\/\|.\)/d' requirements/edx/development.txt \
  > requirements/edx/development-minus-local.txt
RUN pip install -r requirements/pip.txt
RUN pip install -r requirements/edx/development-minus-local.txt

# Set up a Node environment and install Node requirements.
# Must be done after Python requirements, since nodeenv is installed
# via pip.
# The node environment is already 'activated' because its .../bin was put on $PATH.
RUN nodeenv /edx/app/edxapp/nodeenv --node=12.11.1 --prebuilt
COPY package.json package.json
COPY package-lock.json package-lock.json
RUN npm set progress=false && npm install

# Copy over remaining parts of repository (including all code).
COPY . .

# Install Python requirements again in order to capture local projects, which
# were skipped earlier. This should be much quicker than if were installing
# all requirements from scratch.
RUN pip install -r requirements/edx/development.txt

# Update assets.
# This set of commands was extracted from `paver update_assets`.
# Running the commands directly is much faster than invoking Paver.
# The final asset updating steps (collectstatic and compile_sass) are
# service-variant specific and require the Django project to be ready,
# so we do them under the `lms` and `studio` stages.
RUN xmodule_assets common/static/xmodule
RUN mkdir -p common/static/common/js/vendor \
 && mkdir -p common/static/common/css/vendor \
 && find node_modules/@edx/studio-frontend/dist -type f \( -name \*.css -o -name \*.css.map \) | \
    xargs cp --target-directory=common/static/common/css/vendor \
 && find node_modules/@edx/studio-frontend/dist -type f \! -name \*.css \! -name \*.css.map | \
    xargs cp --target-directory=common/static/common/js/vendor \
 && cp -f --target-directory=common/static/common/js/vendor \
    node_modules/backbone.paginator/lib/backbone.paginator.js \
    node_modules/backbone/backbone.js \
    node_modules/bootstrap/dist/js/bootstrap.bundle.js \
    node_modules/hls.js/dist/hls.js \
    node_modules/jquery-migrate/dist/jquery-migrate.js \
    node_modules/jquery.scrollto/jquery.scrollTo.js \
    node_modules/jquery/dist/jquery.js \
    node_modules/moment-timezone/builds/moment-timezone-with-data.js \
    node_modules/moment/min/moment-with-locales.js \
    node_modules/picturefill/dist/picturefill.js \
    node_modules/requirejs/require.js \
    node_modules/underscore.string/dist/underscore.string.js \
    node_modules/underscore/underscore.js \
    node_modules/which-country/index.js \
    node_modules/sinon/pkg/sinon.js \
    node_modules/squirejs/src/Squire.js
# TODO: ^ sinon and square are supposedly dev-only.
RUN NODE_ENV=development \
    STATIC_ROOT_LMS=/edx/var/edxapp/staticfiles \
    STATIC_ROOT_CMS=/edx/var/edxapp/staticfiles/studio \
    JS_ENV_EXTRA_CONFIG="{}" \
    $(npm bin)/webpack --config=webpack.dev.config.js
# TODO: ^ should we do a non-dev build here?

###########################
#  Define LMS target.
FROM base as lms
ENV SERVICE_VARIANT lms
ENV DJANGO_SETTINGS_MODULE lms.envs.$EDX_PLATFORM_SETTINGS

# Finish updating assets, now that code is copied in and we know which
# service variant we are.
RUN ./manage.py lms compile_sass lms
RUN ./manage.py lms collectstatic --ignore "fixtures" --ignore "karma_*.js" --ignore "spec" --ignore "spec_helpers" \
    --ignore "spec-helpers" --ignore "xmodule_js" --ignore "geoip" --ignore "sass" --noinput

# Run gunicorn LMS server on 8000.
# Devstack overrides this command to be a simple Django webserver loop on 18000.
EXPOSE 8000
ENTRYPOINT [ "../edxapp_env" ]
CMD gunicorn \
    -c /edx/app/edxapp/edx-platform/lms/docker_lms_gunicorn.py \
    --name lms \
    --bind=0.0.0.0:8000 \
    --max-requests=1000 \
    --access-logfile \
    - lms.wsgi:application

###########################
#  Define Studio target.
FROM base as studio
ENV SERVICE_VARIANT cms
ENV DJANGO_SETTINGS_MODULE cms.envs.$EDX_PLATFORM_SETTINGS

# Finish updating assets, now that code is copied in and we know which
# service variant we are.
RUN ./manage.py cms compile_sass cms
RUN ./manage.py cms collectstatic --ignore "fixtures" --ignore "karma_*.js" --ignore "spec" --ignore "spec_helpers" \
    --ignore "spec-helpers" --ignore "xmodule_js" --ignore "geoip" --ignore "sass" --noinput

# Run gunicorn Studio server on 8010.
# Devstack overrides this command to be a simple Django webserver loop on 18010.
EXPOSE 8010
ENTRYPOINT [ "../edxapp_env" ]
CMD gunicorn \
    -c /edx/app/edxapp/edx-platform/cms/docker_cms_gunicorn.py \
    --name cms \
    --bind=0.0.0.0:8010 \
    --max-requests=1000 \
    --access-logfile \
    - cms.wsgi:application
