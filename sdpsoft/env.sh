#!/usr/bin/env bash

# Color and text manipulation variables
# Using these colors causes some issues with the terminal. We've gotten complaints, nulling them out
#COLOR_NONE='\033[00m'
#COLOR_RED='\033[01;31m'
#COLOR_GREEN='\033[01;32m'
#COLOR_YELLOW='\033[01;33m'
#COLOR_PURPLE='\033[01;35m'
#COLOR_CYAN='\033[01;36m'
#COLOR_WHITE='\033[01;37m'
#TEXT_BOLD='\033[1m'
#TEXT_UNDERLINE='\033[4m'
#TEXT_NO_UNDERLINE='\033[24m'

COLOR_NONE=''
COLOR_RED=''
COLOR_GREEN=''
COLOR_YELLOW=''
COLOR_PURPLE=''
COLOR_CYAN=''
COLOR_WHITE=''
TEXT_BOLD=''
TEXT_UNDERLINE=''
TEXT_NO_UNDERLINE=''

SDPSOFT_PATH="/prog/sdpsoft"

if [ -z "$LANG" ]; then export LANG="en_US.utf8"; fi

function sdpsoft_menu() {
  printf "${COLOR_PURPLE}"
  printf "\t  ______ ______  ______   ______         ___       \n"
  printf "\t / _____|______)(_____ \ / _____)       / __)  _   \n"
  printf "\t( (____  _     _ _____) | (____   ___ _| |__ _| |_ \n"
  printf "\t \____ \| |   | |  ____/ \____ \ / _ (_   __|_   _)\n"
  printf "\t _____) ) |__/ /| |      _____) ) |_| || |    | |_ \n"
  printf "\t(______/|_____/ |_|     (______/ \___/ |_|     \__)\n"
  printf "\t___________________________________________________\n"
  printf "${COLOR_NONE}"
  printf "${COLOR_GREEN}"
  printf "\nOptional commands:\n"
  printf "${COLOR_NONE}"
  printf -- "\n  --search <software>            Search for available software in SDPSoft\n"
  printf -- "  --silent                       Omits software versions when sourcing. Warnings/Errors will still show\n"
  printf -- "  --help                         Prints this menu\n"
  printf "${COLOR_GREEN}"
  printf "\nUsage examples:\n"
  printf "${COLOR_CYAN}"
  printf "\n  Finding software:\n"
  printf "${COLOR_NONE}"
  printf -- "\n    source /prog/sdpsoft/env.sh --search python\n"
  printf "${COLOR_CYAN}"
  printf "\n  Sourcing software:\n"
  printf "${COLOR_NONE}"
  printf -- "\n    export GCC_VERSION=\"4.9.4\"\n"
  printf -- "    export QT_VERSION=\"5.4.2\"\n"
  printf -- "    export PYTHON_VERSION=\"latest\"\n"
  printf -- "    source /prog/sdpsoft/env.sh\n"
  printf "${COLOR_GREEN}"
  printf "\nLogging:\n"
  printf "${COLOR_NONE}"
  printf "\n    To keep SDPSoft nice and tidy, we're logging which software is being used"
  printf "\n    We're only logging the software name and its version + a timestamp from when it was last used\n"
  printf "${COLOR_GREEN}"
  printf "\nContact:\n"
  printf "${COLOR_NONE}"
  printf "\n    We're here to help! Reach out to us on\n"
  printf "      - Slack: slack.statoil.no #sdpteam\n"
  printf "      - Email: gm_sds_rdi@statoil.com\n"
  printf "\n"
}
# Function to standardise messages outputed by SDPSoft
function sdpsoft_message() {
    # $1 represents the actual message
    # $2 represents the severity level of the message
    message=$1
    message_type=$2
    if [ "$message_type" = "error" ]; then
        printf "${COLOR_RED}"
    elif [ "$message_type" = "warning" ]; then
        printf "${COLOR_YELLOW}"
    else
        printf "${COLOR_GREEN}"
    fi
    printf "\n$message\n\n"
    printf "${COLOR_NONE}"
}
# SDPSofts search function, simply inspecting the SDPSoft path for the string inputed
function sdpsoft_search() {
    search_term=$1
    # software_in_sdpsoft equal to the search string inputed, here is an explaination of the pipes
    # find - in SDPSoft directory, only one level down (meaning sdpsoft root), only folders for an case-insensitive wildcards string match
    # sort - ignore case and use 'version-sort'
    # cut  - away the leading SDPSoft path extractiv only the name of the software that was searched for
    # grep - away any hidden folders
    # grep - for only strings that have 'valid' characters in them
    software_in_sdpsoft=$(find $SDPSOFT_PATH -maxdepth 1 -type d -iname "*$search_term*" | sort -fV | cut -d"/" -f4- | grep -v "^\." | grep "[a-zA-Z0-9\_\-].*[0-9].*")
    if [ "$software_in_sdpsoft" != "" ]; then
        sdpsoft_message "Search results:"
        for software in $software_in_sdpsoft; do
            printf " - $software\n"
        done
        printf "\n"
    else
        sdpsoft_message "Unable to find ${TEXT_UNDERLINE}$search_term${TEXT_NO_UNDERLINE} in SDPSoft" warning
    fi
}
# When updating PATH, LD_LIBRARY_PATH etc, we need to know what character that separates the software name from the version
function find_version_separator() {
    software_path_base=$1
    requested_version=$2
    if [ -d "${software_path_base}_${requested_version}" ]; then
        echo "_"
    elif [ -d "${software_path_base}-${requested_version}" ]; then
        echo "-"
    elif [ -d "${software_path_base}${requested_version}" ]; then
        echo ""
    fi
}

function find_and_source() {
    requested_version=$1
    # Sorry for thorny syntax, it's a way of declaring an array
    declare -a available_versions=("${!2}")
    software_name=$3

    # If the user requestes the get the "latest" version, then some logic is needed to find the last version
    # It boils down to pick the last array element in $available_versions
    if [ "$requested_version" = "latest" ]; then
        # How this logic is implemented depends on which version of bash you have
        bash_version_major=$(echo $BASH_VERSION | cut -d"." -f1)
        bash_version_minor=$(echo $BASH_VERSION | cut -d"." -f2)
        # for bash versions above 4, always use newer method of setting requested_version
	if [ "$bash_version_major" -gt "4" ]; then
    	    requested_version=${available_versions[-1]}
        # for bash version 4.2, newer method is supported, earlier not
	elif [ "$bash_version_major" -eq "4" ]; then
	    if [ "$bash_version_minor" -ge "2" ]; then
    	        requested_version=${available_versions[-1]}
            else
                requested_version="${available_versions[${#available_versions[@]}-1]}"
            fi
        else
            requested_version="${available_versions[${#available_versions[@]}-1]}"
        fi
    fi

    for version in ${available_versions[@]}; do
        
        if [ "$version" == "$requested_version" ]; then
            # Find the separator between the software name and the version
            separator=$(find_version_separator "$SDPSOFT_PATH/$software_name" $requested_version)
            # software_path is the absolute path to the requestes software
            software_path="$SDPSOFT_PATH/${software_name}${separator}${requested_version}"

            # The following if's looks for certain folder and updates paths accordingly
            if [ -d "$software_path/bin" ]; then
                export PATH="$software_path/bin:$PATH"
            fi

            if [ -d "$software_path/lib" ]; then
                if [ -n $LIBRARY_PATH ]; then
	            export LIBRARY_PATH="$software_path/lib:$LIBRARY_PATH"
                else
	            export LIBRARY_PATH="$software_path/lib"
                fi
            fi

            if [ -d "$software_path/lib64" ]; then
                if [ -n $LIBRARY_PATH ]; then
	            export LIBRARY_PATH="$software_path/lib:$LIBRARY_PATH"
                else
	            export LIBRARY_PATH="$software_path/lib"
                fi
            fi

            if [ -d "$software_path/lib" ]; then
                if [ -n $LD_LIBRARY_PATH ]; then
	            export LD_LIBRARY_PATH="$software_path/lib:$LD_LIBRARY_PATH"
                else
	            export LD_LIBRARY_PATH="$software_path/lib"
                fi
            fi

            if [ -d "$software_path/lib64" ]; then
                if [ -n $LD_LIBRARY_PATH ]; then
                    export LD_LIBRARY_PATH="$software_path/lib64:$LD_LIBRARY_PATH"
                else
                    export LD_LIBRARY_PATH="$software_path/lib64"
                fi
            fi

            if [ -d "$software_path/include" ]; then
                if [ -n $CPATH ]; then
                    export CPATH="$software_path/include:$CPATH"
                else
                    export CPATH="$software_path/include"
                fi
                if [ -n $C_INCLUDE_PATH ]; then
                    export C_INCLUDE_PATH="$software_path/include:$C_INCLUDE_PATH"
                else
                    export C_INCLUDE_PATH="$software_path/include"
                fi
                if [ -n $CPLUS_INCLUDE_PATH ]; then
                    export CPLUS_INCLUDE_PATH="$software_path/include:$CPLUS_INCLUDE_PATH"
                else
                    export CPLUS_INCLUDE_PATH="$software_path/include"
                fi
                if [ -n $OBJC_INCLUDE_PATH ]; then
                    export OBJC_INCLUDE_PATH="$software_path/include:$OBJC_INCLUDE_PATH"
                else
                    export OBJC_INCLUDE_PATH="$software_path/include"
                fi
            fi

            if [ -d "$software_path/man" ]; then
                if [ -n $MAN_INCLUDE_PATH ]; then
                    export MANPATH="$software_path/man:$MANPATH"
                else
                    export MANPATH="$software_path/man"
                fi
            fi

            # If SILENT_OUTPUT is unset or empty
            if [ -z "$SILENT_OUTPUT" ]; then
                printf "${COLOR_GREEN}"
                printf "$software_name: $requested_version\n"
                printf "${COLOR_NONE}"
            fi
           
            # Logging of software usage
            timestamp=$(date -u +"%F_%H:%M:%S")
            # Using sed -i causes a problem with writing temporary sed-file to /prog/sdpsoft
            # which normal users do not have access to, resulting in failed Jenkins builds etc..
            # Therefore, setting temp to the sed'ed output and use that to populate .software.log became
            # the working solution
            temp=$(sed "/^${software_name}${separator}${requested_version}@/d" $SDPSOFT_PATH/.software.log)
            echo $temp | tr " " "\n" > $SDPSOFT_PATH/.software.log
            echo "${software_name}${separator}${requested_version}@$timestamp" >> $SDPSOFT_PATH/.software.log

            # Returning 0 here will exit this function
            return 0
        fi
    done
    # If no version were found, then print all the available versions for the software requested
    printf "${COLOR_YELLOW}"
    printf "$software_name: $requested_version not found!\n"
    printf "Available versions for $software_name:\n"
    for version in ${available_versions[@]}; do
        echo $version
    done
    printf "${COLOR_NONE}"
    return 2
}

if [ "$1" = "help" -o "$1" = "--help" -o "$1" = "-h" -o "$1" = "menu" -o "$1" = "--menu" ]; then
    sdpsoft_menu
    return 0
elif [ "$1" = "--search" ]; then
    if [ "$2" = "" ]; then
        sdpsoft_message "No search term defined! Please define a search term" warning
        sdpsoft_menu
    else
        sdpsoft_search $2
    fi
    return 0
else
    if [ "$1" = "--silent" ]; then
        SILENT_OUTPUT=true
    fi

  ################# LEGACY STUFF START ##############################
# Enable legacy stuff which were defaults in the old source scripts
#  INTELXESTATOIL="/prog/Intel/studioxe/composer_xe_2011_sp1.11.339"
#  INTELCCSTATOIL="/prog/Intel/studioxe/bin/compilervars.sh"
#  INTELCCSTATOIL_OLD="/prog/Intel/intel_cc_11/bin/iccvars.sh"
#  INTELMKLSTATOIL="/prog/Intel/studioxe/mkl/bin/mklvars.sh"
#  INTELMKLSTATOIL_OLD="/prog/Intel/mkl10cluster/tools/environment/mklvarsem64t.sh"

# Currently, no usage information for intel_mpi in the help menu provided. Waiting to see how much it is used first.

    if [ "$INTEL_MPI" = "yes" ]; then
        if [ -n "$OPENMPI_VERSION" ]; then
            printf "${COLOR_RED}"
            printf "You are trying to source with both intelmpi and openmpi\n"
            printf "Aborting to avoid unexpected behaviour\n"
            printf "${COLOR_NONE}"
            exit 2
        else
            export MPI="/prog/Intel/intel_mpi_4.1"
            export PATH="$MPI/bin64:$PATH"
            export CPATH="$MPI/include64:$CPATH"
            export C_INCLUDE_PATH="$MPI/include64:$C_INCLUDE_PATH"
            export CPLUS_INCLUDE_PATH="$MPI/include64:$CPLUS_INCLUDE_PATH"
            export OBJC_INCLUDE_PATH="$MPI/include64:$OBJC_INCLUDE_PATH"
            export FPATH="$MPI/include64:$FPATH"
            export LIBRARY_PATH="$MPI/lib64:$LIBRARY_PATH"
            export LD_LIBRARY_PATH="$MPI/lib64:$LD_LIBRARY_PATH"
            printf "${COLOR_GREEN}${MPI}${COLOR_NONE}\n"
        fi
    fi
    
      ################# LEGACY STUFF END ##############################

    # The following if's is just a simple check to look for what software the user requested
    # Most of the software are so generic that they can use the find_and_source function
    # but there are some edge cases that needs to be treated differently, e.g. madagascar
    # Knowing if some software needs special treatment is something you could find in the software docs
    # or if the software have some special sourcing mechanisms
    
    if [ -n "$ARPACK_NG_VERSION" ]; then
        ARPACK_NG_VERSIONS=(
            "3.4.0"
        )
        find_and_source $ARPACK_NG_VERSION ARPACK_NG_VERSIONS[@] arpack-ng
    fi
    
    if [ -n "$ASTYLE_VERSION" ]; then
        ASTYLE_VERSIONS=(
            "2.05.1"
        )
        find_and_source $ASTYLE_VERSION ASTYLE_VERSIONS[@] astyle
    fi
    
    if [ -n "$AUTOCONF_VERSION" ]; then
        AUTOCONF_VERSIONS=(
            "2.69"
        )
        find_and_source $AUTOCONF_VERSION AUTOCONF_VERSIONS[@] autoconf
    fi
    
    if [ -n "$AUTOMAKE_VERSION" ]; then
        AUTOMAKE_VERSIONS=(
            "1.15"
        )
        find_and_source $AUTOMAKE_VERSION AUTOMAKE_VERSIONS[@] automake
    fi
    
    if [ -n "$BINUTILS_VERSION" ]; then
        BINUTILS_VERSIONS=(
            "2.28"
        )
        find_and_source $BINUTILS_VERSION BINUTILS_VERSIONS[@] binutils
    fi
    
    if [ -n "$BOOST_VERSION" ]; then
        BOOST_VERSIONS=(
            "1.44.0"
            "1.45"
            "1.58"
            "1.66.0"
        )
        find_and_source $BOOST_VERSION BOOST_VERSIONS[@] boost
    fi
    
    if [ -n "$CHECK_VERSION" ]; then
        CHECK_VERSIONS=(
             "0.9.5"
        )
        find_and_source $CHECK_VERSION CHECK_VERSIONS[@] check
    fi
    
    if [ -n "$CLOOG_VERSION" ]; then
        CLOOG_VERSIONS=(
             "0.16.2"
        )
        find_and_source $CLOOG_VERSION CLOOG_VERSIONS[@] cloog
    fi
    
    if [ -n "$CMAKE_VERSION" ]; then
        CMAKE_VERSIONS=(
             "3.10.2"
        )
        find_and_source $CMAKE_VERSION CMAKE_VERSIONS[@] cmake
    fi

    if [ -n "$COIN3D_VERSION" ]; then
        COIN3D_VERSIONS=(
             "3.1.3"
        )
        find_and_source $COIND3D_VERSION COIND3D_VERSIONS[@] coin3d
    fi
    
    if [ -n "$CPPUNIT_VERSION" ]; then
        CPPUNIT_VERSIONS=(
             "1.12.0"
        )
        find_and_source $CPPUNIT_VERSION CPPUNIT_VERSIONS[@] cppunit
    fi
    
    if [ -n "$CURL_VERSION" ]; then
        CURL_VERSIONS=(
             "7.21.1"
             "7.56.0"
        )
        find_and_source $CURL_VERSION CURL_VERSIONS[@] curl
    fi
    
    if [ -n "$DELPHI_VERSION" ]; then
        DELPHI_VERSIONS=(
             "41_su40"
        )
        find_and_source $DELPHI_VERSION DELPHI_VERSIONS[@] delphi
    fi
    
    if [ -n "$DERE_VERSION" ]; then
        DERE_VERSIONS=(
             "1.0"
        )
        find_and_source $DERE_VERSION DERE_VERSIONS[@] dere
    fi
    
    if [ -n "$DUNE_VERSION" ]; then
        DUNE_VERSIONS=(
             "2.5.1"
        )
        find_and_source $DUNE_VERSION DUNE_VERSIONS[@] dune
    fi
    
    if [ -n "$EXPAT_VERSION" ]; then
        EXPAT_VERSIONS=(
             "2.1.0"
        )
        find_and_source $EXPAT_VERSION EXPAT_VERSIONS[@] expat
    fi
    
    if [ -n "$FFTW_VERSION" ]; then
        FFTW_VERSIONS=(
             "2.1.5"
             "3.2.1"
             "3.3.3"
             "3.3.4"
        )
        find_and_source $FFTW_VERSION FFTW_VERSIONS[@] fftw
    fi
    
    if [ -n "$FREETYPE_VERSION" ]; then
        FREETYPE_VERSIONS=(
             "2.4.12"
        )
        find_and_source $FREETYPE_VERSION FREETYPE_VERSIONS[@] freetype
    fi
    
    if [ -n "$GCC_VERSION" ]; then
        GCC_VERSIONS=(
            "4.2.4"
            "4.6.1"
            "4.8.2"
            "4.9.4"
            "7.2.0"
            "7.3.0"
        )
        find_and_source $GCC_VERSION GCC_VERSIONS[@] gcc
    fi
    
    if [ -n "$GDB_VERSION" ]; then
        GDB_VERSIONS=(
              "8.0"
        )
        find_and_source $GDB_VERSION GDB_VERSIONS[@] gdb
    fi
    
    if [ -n "$GIT_VERSION" ]; then
        GIT_VERSIONS=(
            "1.8.2"
            "1.8.3"
            "2.4.0"
            "2.7.3"
            "2.8.0"
            "2.12.2"
            "2.16.1"
        )
        find_and_source $GIT_VERSION GIT_VERSIONS[@] git
    fi
    
    if [ -n "$GIT_EXTRAS_VERSION" ]; then
        GIT_EXTRAS_VERSIONS=(
            "3.0.0"
        )
        find_and_source $GIT_EXTRAS_VERSION GIT_EXTRAS_VERSIONS[@] git-extras
    fi
    
    if [ -n "$GIT_LFS_VERSION" ]; then
        GIT_LFS_VERSIONS=(
            "2.3.0"
        )
        find_and_source $GIT_LFS_VERSION GIT_LFS_VERSIONS[@] git-lfs
    fi

    if [ -n "$GLIB_VERSION" ]; then
        GLIB_VERSIONS=(
            "2.54.0"
        )
        find_and_source $GLIB_VERSION GLIB_VERSIONS[@] glib
    fi

    if [ -n "$GLIBC_VERSION" ]; then
        GLIBC_VERSIONS=(
            "2.17"
            "2.23"
        )
        find_and_source $GLIBC_VERSION GLIBC_VERSIONS[@] glibc
    fi
    
    if [ -n "$GMP_VERSION" ]; then
        GMP_VERSIONS=(
            "5.0.2"
            "5.0.5"
            "5.1.3"
            "6.1.2"
        )
        find_and_source $GMP_VERSION GMP_VERSIONS[@] gmp
    fi
    
    if [ -n "$GNUPLOT_VERSION" ]; then
        GNUPLOT_VERSIONS=(
            "4.6.5"
        )
        find_and_source $GNUPLOT_VERSION GNUPLOT_VERSIONS[@] gnuplot
    fi
    
    if [ -n "$GO_VERSION" ]; then
        GO_VERSIONS=(
            "1.2.1"
            "1.4.2"
            "1.6"
            "1.7.3"
        )
        find_and_source $GO_VERSION GO_VERSIONS[@] go
        if [ "$?" == "0" ]; then
            separator=$(find_version_separator "$SDPSOFT_PATH/go" $GO_VERSION)
            export GOROOT="$SDPSOFT_PATH/go${separator}${GO_VERSION}"
        fi
    fi
    
    if [ -n "$GRACE_VERSION" ]; then
        GRACE_VERSIONS=(
            "5.99.0"
        )
        find_and_source $GRACE_VERSION GRACE_VERSIONS[@] grace
    fi
    
    if [ -n "$GRT_VERSION" ]; then
        GRT_VERSIONS=(
            "1.4.0"
            "1.4.2"
            "1.5.0"
            "1.5.2"
        )
        find_and_source $GRT_VERSION GRT_VERSIONS[@] GRT
    fi
    
    if [ -n "$GSL_VERSION" ]; then
        GSL_VERSIONS=(
            "1.9"
        )
        find_and_source $GSL_VERSION GSL_VERSIONS[@] gsl
    fi
    
    if [ -n "$HDF5_VERSION" ]; then
        HDF5_VERSIONS=(
            "1.8.8"
        )
        find_and_source $HDF5_VERSION HDF5_VERSIONS[@] hdf5
    fi
    
    if [ -n "$ICU_VERSION" ]; then
        ICU_VERSIONS=(
            "4.2.1"
        )
        find_and_source $ICU_VERSION ICU_VERSIONS[@] icu
    fi
    
    if [ -n "$IMAGEMAGICK_VERSION" ]; then
        IMAGEMAGICK_VERSIONS=(
            "6.6.1-5"
        )
        find_and_source $IMAGEMAGICK_VERSION IMAGEMAGICK_VERSIONS[@] ImageMagick
    fi
    
    if [ -n "$JDK_VERSION" ]; then
        JDK_VERSIONS=(
            "1.6.0_16"
            "1.6.0_27"
            "1.6.0_45"
            "1.7.0_07"
            "1.7.0_11"
            "1.7.0_25"
            "1.7.0_45"
            "1.8.0_11"
            "1.8.0_25"
            "1.8.0_121"
            "1.8.0_162"
        )
        find_and_source $JDK_VERSION JDK_VERSIONS[@] jdk
    fi
    
    if [ -n "$JQ_VERSION" ]; then
        JQ_VERSIONS=(
            "1.5"
        )
        find_and_source $JQ_VERSION JQ_VERSIONS[@] jq
    fi
    
    if [ -n "$JSEISIO_VERSION" ]; then
        JSEISIO_VERSIONS=(
            "v1.0"
            "v1.1"
        )
        find_and_source $JSEISIO_VERSION JSEISIO_VERSIONS[@] jseisio
    fi
    
    if [ -n "$JULIA_VERSION" ]; then
        JULIA_VERSIONS=(
            "0.4.6"
        )
        find_and_source $JULIA_VERSION JULIA_VERSIONS[@] julia
    fi
    
    if [ -n "$KDIFF3_VERSION" ]; then
        KDIFF3_VERSIONS=(
            "0.9.96"
        )
        find_and_source $KDIFF3_VERSION KDIFF3_VERSIONS[@] kdiff3
    fi
    
    if [ -n "$KERNELTOMO_VERSION" ]; then
        KERNELTOMO_VERSIONS=(
            "1.0"
        )
        find_and_source $KERNELTOMO_VERSION KERNELTOMO_VERSIONS[@] KernelTomo
    fi
    
    if [ -n "$LAPACK_VERSION" ]; then
        LAPACK_VERSIONS=(
            "3.7.0"
        )
        find_and_source $LAPACK_VERSION LAPACK_VERSIONS[@] lapack
    fi

    if [ -n "$LIBECL_VERSION" ]; then
        LIBECL_VERSIONS=(
            "2.3.a2"
            "2.3.a5"
        )
        find_and_source $LIBECL_VERSION LIBECL_VERSIONS[@] libecl
    fi

    if [ -n "$LIBEVENT_VERSION" ]; then
        LIBEVENT_VERSIONS=(
            "2.0.9-rc"
        )
        find_and_source $LIBEVENT_VERSION LIBEVENT_VERSIONS[@] libevent
    fi
    
    if [ -n "$LIBFFI_VERSION" ]; then
        LIBFFI_VERSIONS=(
            "3.0.9"
            "3.2.1"
        )
        find_and_source $LIBFFI_VERSION LIBFFI_VERSIONS[@] libffi
    fi
    
    if [ -n "$LIBNOTIFY_VERSION" ]; then
        LIBNOTIFY_VERSIONS=(
            "0.4.4"
        )
        find_and_source $LIBNOTIFY_VERSION LIBNOTIFY_VERSIONS[@] libnotify
    fi
    
    if [ -n "$LIBSTATOIL_VERSION" ]; then
        LIBSTATOIL_VERSIONS=(
            "0.1"
            "0.2"
        )
        find_and_source $LIBSTATOIL_VERSION LIBSTATOIL_VERSIONS[@] libstatoil
    fi
    
    if [ -n "$LIBTASN1_VERSION" ]; then
        LIBTASN1_VERSIONS=(
            "4.12"
        )
        find_and_source $LIBTASN1_VERSION LIBTASN1_VERSIONS[@] libtasn1
    fi
    
    if [ -n "$LIBUNISTRING_VERSION" ]; then
        LIBUNISTRING_VERSIONS=(
            "0.9.7"
        )
        find_and_source $LIBUNISTRING_VERSION LIBUNISTRING_VERSIONS[@] libunistring
    fi
    
    if [ -n "$MADAGASCAR_VERSION" ]; then
        # Let Madagascar be source with their own scripts that they provide
        MADAGASCAR_FOUND=0
        if [ -d "$SDPSOFT_PATH/madagascar_$MADAGASCAR_VERSION" ]; then
            MADAGASCAR_FOUND=1
            source "$SDPSOFT_PATH/madagascar_$MADAGASCAR_VERSION/share/madagascar/etc/env.sh"
        elif [ -d "$SDPSOFT_PATH/madagascar-$MADAGASCAR_VERSION" ]; then
            MADAGASCAR_FOUND=1
            source "$SDPSOFT_PATH/madagascar-$MADAGASCAR_VERSION/share/madagascar/etc/env.sh"
        elif [ -d "$SDPSOFT_PATH/madagascar$MADAGASCAR_VERSION" ]; then
            MADAGASCAR_FOUND=1
            source "$SDPSOFT_PATH/madagascar$MADAGASCAR_VERSION/share/madagascar/etc/env.sh"
        fi
        if [ "$MADAGASCAR_FOUND" = "1" ]; then
            if [ "$1" != "--silent" ]; then
                printf "${COLOR_GREEN}"
                printf "madagascar $MADAGASCAR_VERSION\n"
                printf "${COLOR_NONE}"
            fi
        else
            printf "${COLOR_YELLOW}"
            printf "madagascar version $MADAGASCAR_VERSION not found. Try searching for versions.\n"
            printf "${COLOR_NONE}"
        fi
    fi
    
    if [ -n "$MERCURIAL_VERSION" ]; then
        MERCURIAL_VERSIONS=(
            "1.6"
        )
        find_and_source $MERCURIAL_VERSION MERCURIAL_VERSIONS[@] mercurial
    fi
    
    if [ -n "$MPC_VERSION" ]; then
        MPC_VERSIONS=(
            "0.9"
        )
        find_and_source $MPC_VERSION MPC_VERSIONS[@] mpc
    fi
    
    if [ -n "$MPFR_VERSION" ]; then
        MPFR_VERSIONS=(
            "2.4.2"
            "3.1.0"
        )
        find_and_source $MPFR_VERSION MPFR_VERSIONS[@] mpfr
    fi
    
    if [ -n "$MPICH_VERSION" ]; then
        MPICH_VERSIONS=(
            "1.2.6_i686"
            "1.2.6_x86_64"
        )
        find_and_source $MPICH_VERSION MPICH_VERSIONS[@] mpich
    fi
    
    if [ -n "$MPICH2_VERSION" ]; then
        MPICH2_VERSIONS=(
            "1.3.2"
        )
        find_and_source $MPICH2_VERSION MPICH2_VERSIONS[@] mpich2
    fi
    
    if [ -n "$NETCDF_VERSION" ]; then
        NETCDF_VERSIONS=(
            "3"
        )
        find_and_source $NETCDF_VERSION NETCDF_VERSIONS[@] netcdf
    fi
    
    if [ -n "$NETTLE_VERSION" ]; then
        NETTLE_VERSIONS=(
            "3.3"
        )
        find_and_source $NETTLE_VERSION NETTLE_VERSIONS[@] nettle
    fi
    
    if [ -n "$NODE_VERSION" ]; then
        NODE_VERSIONS=(
            "0.10.12"
            "8.11.2"
            "8.11.3"
        )
        find_and_source $NODE_VERSION NODE_VERSIONS[@] node
    fi
    
    if [ -n "$OCTAVE_VERSION" ]; then
        OCTAVE_VERSIONS=(
            "4.2.1"
        )
        find_and_source $OCTAVE_VERSION OCTAVE_VERSIONS[@] octave
    fi
    
    if [ -n "$OPENBLAS_VERSION" ]; then
        OPENBLAS_VERSIONS=(
            "0.2.14"
        )
        find_and_source $OPENBLAS_VERSION OPENBLAS_VERSIONS[@] openblas
    fi
    
    if [ -n "$OPENMPI_VERSION" ]; then
        OPENMPI_VERSIONS=(
            "1.2.5"
            "1.2.6"
            "1.2.8"
            "1.4.2"
            "1.6.3"
            "1.6.5"
            "1.8.4"
        )
        find_and_source $OPENMPI_VERSION OPENMPI_VERSIONS[@] openmpi
        if [ "$?" == "0" ]; then
            separator=$(find_version_separator "$SDPSOFT_PATH/openmpi" $OPENMPI_VERSION)
            export MPI="$SDPSOFT_PATH/openmpi${separator}$OPENMPI_VERSION"
            export FPATH="$MPI/include:$FPATH"
            export OPAL_PREFIX="$MPI"
        fi
    fi

    if [ -n "$OPENSSL_VERSION" ]; then
        OPENSSL_VERSIONS=(
            "1.0.2l"
            "1.1.0f"
        )
        find_and_source $OPENSSL_VERSION OPENSSL_VERSIONS[@] openssl
    fi
    
    if [ -n "$OPTARADON_VERSION" ]; then
        OPTARADON_VERSIONS=(
            "r1"
        )
        find_and_source $OPTARADON_VERSION OPTARADON_VERSIONS[@] OptaRadon
    fi
    
    if [ -n "$OSG_VERSION" ]; then
        OSG_VERSIONS=(
            "2.8.2"
        )
        find_and_source $OSG_VERSION OSG_VERSIONS[@] osg
    fi
    
    if [ -n "$P11_KIT_VERSION" ]; then
        P11_KIT_VERSIONS=(
            "0.23.2"
        )
        find_and_source $P11_KIT_VERSION P11_KIT_VERSIONS[@] p11-kit
    fi
    
    if [ -n "$PCRE_VERSION" ]; then
        PCRE_VERSIONS=(
            "8.40"
        )
        find_and_source $PCRE_VERSION PCRE_VERSIONS[@] pcre
    fi
    
    if [ -n "$PHANTOMJS_VERSION" ]; then
        PHANTOMJS_VERSIONS=(
            "1.6.2-linux-x86_64-dynamic"
        )
        find_and_source $PHANTOMJS_VERSION PHANTOMJS_VERSIONS[@] phantomjs
    fi
    
    if [ -n "$PHP_VERSION" ]; then
        PHP_VERSIONS=(
            "5.3.8"
        )
        find_and_source $PHP_VERSION PHP_VERSIONS[@] php
    fi
    
    if [ -n "$PPL_VERSION" ]; then
        PPL_VERSIONS=(
            "0.11.2"
        )
        find_and_source $PPL_VERSION PPL_VERSIONS[@] ppl
    fi
    
    if [ -n "$PUMA_VERSION" ]; then
        PUMA_VERSIONS=(
            "v1.0"
            "v1.1"
            "v1.2"
        )
        find_and_source $PUMA_VERSION PUMA_VERSIONS[@] puma
    fi
    
    if [ -n "$PYTHON_VERSION" ]; then
        PYTHON_VERSIONS=(
            "2.4"
            "2.6"
            "2.6.7"
            "2.7.3"
            "2.7.6"
            "2.7.11"
            "2.7.13"
            "2.7.14"
            "2.7.15"
            "3.3.2"
            "3.4.2"
            "3.6.1"
            "3.6.2"
            "3.6.4"
        )
        find_and_source $PYTHON_VERSION PYTHON_VERSIONS[@] python
    fi

    if [ -n "$QHULL_VERSION" ]; then
        QHULL_VERSIONS=(
            "7.2.0"
        )
        find_and_source $QHULL_VERSION QHULL_VERSIONS[@] qhull
    fi
    
    if [ -n "$QRUPDATE_VERSION" ]; then
        QRUPDATE_VERSIONS=(
            "1.1.2"
        )
        find_and_source $QRUPDATE_VERSION QRUPDATE_VERSIONS[@] qrupdate
    fi
    
    if [ -n "$QT_VERSION" ]; then
        QT_VERSIONS=(
             "3.3.5"
             "4.6"
             "4.6.2"
             "4.7.1"
             "4.8.4"
             "4.8.6"
             "5.4.2"
             "5.9.1"
             "5.9.6"
             "5.11.1"
        )
        find_and_source $QT_VERSION QT_VERSIONS[@] qt-x11
          if [ "$?" == "0" ]; then
              separator=$(find_version_separator "$SDPSOFT_PATH/qt-x11" $QT_VERSION)
              export QT_PATH="$SDPSOFT_PATH/qt-x11${separator}${QT_VERSION}"
          fi
    fi
    
    if [ -n "$RUBY_VERSION" ]; then
        RUBY_VERSIONS=(
            "1.8.7"
            "1.9.3"
            "2.0.0"
        )
        find_and_source $RUBY_VERSION ruby_VERSIONS[@] ruby
          if [ "$?" == "0" ]; then
              separator=$(find_version_separator "$SDPSOFT_PATH/ruby" $RUBY_VERSION)
              export GEM_HOME="$SDPSOFT_PATH/ruby${separator}${RUBY_VERSION}/lib/ruby/gems/$RUBY_VERSION"
          fi
    fi
    
    if [ -n "$SCALA_VERSION" ]; then
        SCALA_VERSIONS=(
            "2.8.0"
            "2.9.1"
            "2.10.0"
        )
        find_and_source $SCALA_VERSION SCALA_VERSIONS[@] scala
    fi
    
    if [ -n "$SCONS_VERSION" ]; then
        SCONS_VERSIONS=(
            "2.1.0"
        )
        find_and_source $SCONS_VERSION SCONS_VERSIONS[@] scons
    fi
    
    if [ -n "$SCREENSEIS_VERSION" ]; then
        SCREENSEIS_VERSIONS=(
            "v.2.6"
            "v.2.6.1_amd"
            "v.2.6.2_amd"
            "v.2.6.3_amd"
        )
        find_and_source $SCREENSEIS_VERSION SCREENSEIS_VERSIONS[@] screenseis
    fi
    
    if [ -n "$SCREENSHOT_VERSION" ]; then
        SCREENSHOT_VERSIONS=(
            "v2.0"
            "v2.0_oslo"
        )
        find_and_source $SCREENSHOT_VERSION SCREENSHOT_VERSIONS[@] ScreenShot
    fi
    
    if [ -n "$SEPLIB_VERSION" ]; then
        SEPLIB_VERSIONS=(
            "6.5.3"
        )
        find_and_source $SEPLIB_VERSION SEPLIB_VERSIONS[@] seplib
    fi
    
    if [ -n "$SIMVOLEON_VERSION" ]; then
        SIMVOLEON_VERSIONS=(
            "2.0.1"
        )
        find_and_source $SIMVOLEON_VERSION SIMVOLEON_VERSIONS[@] simvoleon
    fi
    
    if [ -n "$SOQT_VERSION" ]; then
        SOQT_VERSIONS=(
            "1.5.0"
        )
        find_and_source $SOQT_VERSION SOQT_VERSIONS[@] soqt
    fi
    
    if [ -n "$SUITESPARSE_VERSION" ]; then
        SUITESPARSE_VERSIONS=(
            "4.5.4"
        )
        find_and_source $SUITESPARSE_VERSION SUITESPARSE_VERSIONS[@] suitesparse
    fi

    if [ -n "$SU_VERSION" ]; then
        SU_VERSIONS=(
            "40"
            "42"
            "43_R3"
            "43_R6"
        )
        find_and_source $SU_VERSION SU_VERSIONS[@] SU
    fi
    
    if [ -n "$SVFTOOLS_VERSION" ]; then
        SVFTOOLS_VERSIONS=(
            "r4"
            "r5"
            "r12"
            "r17"
        )
        find_and_source $SVFTOOLS_VERSION SVFTOOLS_VERSIONS[@] svftools
    fi
    
    if [ -n "$TCL_VERSION" ]; then
        TCL_VERSIONS=(
            "8.4.20"
            "8.6.3"
        )
        find_and_source $TCL_VERSION TCL_VERSIONS[@] tcl
    fi
    
    if [ -n "$TIGER_VERSION" ]; then
        TIGER_VERSIONS=(
            "v0.7.1"
            "v0.7.2"
            "v0.7.2-1"
        )
        find_and_source $TIGER_VERSION TIGER_VERSIONS[@] tiger
    fi
    
    if [ -n "$TK_VERSION" ]; then
        TK_VERSIONS=(
            "8.4.20"
            "8.6.3"
        )
        find_and_source $TK_VERSION TK_VERSIONS[@] tk
    fi
    
    if [ -n "$TMUX_VERSION" ]; then
        TMUX_VERSIONS=(
            "2.6"
        )
        find_and_source $TMUX_VERSION TMUX_VERSIONS[@] tmux
    fi

    if [ -n "$TORQUE_VERSION" ]; then
        TORQUE_VERSIONS=(
            "6.1.0"
        )
        find_and_source $TORQUE_VERSION TORQUE_VERSIONS[@] torque
    fi
    
    if [ -n "$WX_VERSION" ]; then
        WX_VERSIONS=(
            "2.9.1.1"
        )
        find_and_source $WX_VERSION WX_VERSIONS[@] wx
    fi
    
    if [ -n "$ZEROMQ_VERSION" ]; then
        ZEROMQ_VERSIONS=(
            "4.2.1"
        )
        find_and_source $ZEROMQ_VERSION ZEROMQ_VERSIONS[@] zeromq
    fi
fi
