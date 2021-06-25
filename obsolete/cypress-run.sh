#!/usr/bin/env -i bash

# Find this scripts parent PID
PARENT_PID=$(cat /proc/$$/status | grep -i ppid | awk '{print $2}')
# Then find the parents display and use that to launch Cypress
DISPLAY=$(cat /proc/${PARENT_PID}/environ | awk -v RS='\0' -F= '$1=="DISPLAY" {print $2}')
export DISPLAY=${DISPLAY}

# Find the user who's executing this script
USER=$(id -u -n)
export USER=${USER}
export HOME="/private/$USER"

# Set PATH to defaults
export PATH="/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin"

export LANG="en_US.UTF-8"

# Unset everything that could cause interference with Cypress
unset LD_LIBRARY_PATH
unset LIBRARY_PATH
unset CPLUS_INCLUDE_PATH
unset C_INCLUDE_PATH

function start_cypress() {
  export QT_VERSION="5.4.2"
  export GCC_VERSION="4.9.4"
  export ICU_VERSION="4.2.1"
  export GLIBC_VERSION="2.23"
  export LD_LIBRARY_PATH="/lib64:$LD_LIBRARY_PATH"
  export LD_LIBRARY_PATH="/usr/lib64:$LD_LIBRARY_PATH"
  source /prog/sdpsoft/env.sh --silent >/dev/null 2>&1

  export QT_XKB_CONFIG_ROOT=/usr/share/X11/xkb
  export TZ=/etc/localtime

  "./cypress/cypress"
  exit 0
}

if [ ! "$1" ]; then
  #printf "\nINFO: You didn't provide any zip-file, assuming you just want to run the latest unzipped Cypress\n"
  if [ ! -L "cypress" ]; then
    printf "\nERROR: Unable to find any cypress symlink, you should run this script pointing to a Cypress-zipfile first\n"
    exit 2
  fi
  start_cypress
else
  BUILD_FILE="$1"
  FILE_NAME=$(echo $BUILD_FILE | rev  | cut -d"/" -f1 | rev)
  if [ ! "${FILE_NAME: -4}" == ".zip" ]; then
    printf "\nERROR: Seems like you didn't provide a zip-file, aborting\n"
    exit 2
  fi
  if [ ! -f "${BUILD_FILE}" ]; then
    printf "\nERROR: The file you provided doesn't exist! Aborting\n"
    exit 2
  fi
  BUILD_NUMBER=$(echo $BUILD_FILE | cut -d"_" -f2 | cut -d"." -f1)
  DIR_NAME="cypress_$BUILD_NUMBER"
  if [ ! -f "./${FILE_NAME}" ]; then
    #printf "\nINFO: Making a local copy of file ${BUILD_FILE}\n"
    cp $BUILD_FILE ./
  fi
  if [ ! -d "./${DIR_NAME}" ]; then
    unzip -q $FILE_NAME
    mv Cypress $DIR_NAME
  fi
  if [ -L "cypress" ]; then
    rm -f ./cypress
  fi
  ln -s ./${DIR_NAME} cypress
  start_cypress
fi
