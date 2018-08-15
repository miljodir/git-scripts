#!/bin/sh



SDPPATH="/prog/sdpsoft"

################## START OF DEPRECATION #################
printf "\n********************************************\n\n"
printf "DEPRECATION WARNING:\n"
printf "  You are using the deprecated script /prog/sdpsoft/environment.sh to source SDPSoft\n"
printf "  You should use the new source scripts (env.sh and env.csh) instead\n"
printf "  Read more on how to use the new scripts at https://sdp.statoil.no/sdpsoft\n"
printf "LOGGING NOTE:\n"
printf "  The usernames of those using this script will be logged\n"
printf "  We're doing this to help people over to the new scripts and to get a smoother transition\n"
printf "\n*******************************************\n\n"

#The space in grep here is crucial. Unable to find csh eqvivalent of $, this was the solution
grep -q "^$USER $" $SDPPATH/.user.log
if [ "$?" != "0" ]; then
    echo "$USER " >> $SDPPATH/.user.log
fi
################ END OF DEPRECATION #####################

if [ -z "$LANG" ]; then export LANG="en_US.utf8"; fi

# Commented out by afel - 03/03/2014
#INTELCCSTATOIL="/prog/Intel/studioxe2013/bin/compilervars.sh"
#INTELCCSTATOIL_OLD="/prog/Intel/studioxe/bin/compilervars.sh"
#INTELFCSTATOIL_OLD="/prog/Intel/intel_fc_11/bin/ifortvars.sh"

INTELXESTATOIL="/prog/Intel/studioxe/composer_xe_2011_sp1.11.339"
INTELCCSTATOIL="/prog/Intel/studioxe/bin/compilervars.sh"
INTELCCSTATOIL_OLD="/prog/Intel/intel_cc_11/bin/iccvars.sh"
#INTELFCSTATOIL_OLD="/prog/Intel/intel_fc_11/bin/ifortvars.sh"

# Intel MKL Kernel
# Commented out by afel - 03/03/2014
#INTELMKLSTATOIL="/prog/Intel/studioxe2013/mkl/bin/mklvars.sh"
#INTELMKLSTATOIL_OLD="/prog/Intel/studioxe/mkl/bin/mklvars.sh"
INTELMKLSTATOIL="/prog/Intel/studioxe/mkl/bin/mklvars.sh"
INTELMKLSTATOIL_OLD="/prog/Intel/mkl10cluster/tools/environment/mklvarsem64t.sh"

MPIARG=$1
EXIT=0

# Open-MPI
OPENMPI_STD_VER="1.8.4"
OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"

# Intel MPI
INTELMPI=0

# returns 0 if the script is interactive, 
# and 1 if not
function is_interactive() {
	if [ -z "$PS1" ]; then
		echo 0
	else
		echo 1
	fi
}
INTERACTIVE=$(is_interactive)


if [ -z $MPIARG ]; then
    echo "Using OpenMPI as standard MPI interface (default)"
    echo "To use other MPI interfaces, add the argument \"-help\" to the environment file"
    MPI="${SDPPATH}/${OPENMPI_STD}"
elif [ $MPIARG == "mpich_x86_64" -o $MPIARG == "mpich" ]; then
    MPI="${SDPPATH}/mpich-1.2.6_x86_64"
    echo "Using MPICH 64-bit version as standard MPI interface"
elif [ "$MPIARG" == "mpich2" ]; then
    MPI="${SDPPATH}/mpich2-1.3.2"
    echo "Using MPICH2 v1.3.2 as standard MPI interface"
elif [ "$MPIARG" == "openmpi" ]; then
    echo "Using OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    MPI="${SDPPATH}/${OPENMPI_STD}"
elif [ "$MPIARG" == "openmpi_132" ]; then
    OPENMPI_STD_VER="1.3.2"
    OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"
    echo "Using EXPERIMENTAL OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    MPI="/usr/lib64/openmpi/1.3.2-gcc"
    export OMPI_MCA_btl="tcp,self" # to use only ethernet(tcp) and loopback
elif [ "$MPIARG" == "openmpi_142" ]; then
    OPENMPI_STD_VER="1.4.2"
    OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"
    echo "Using OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    MPI="${SDPPATH}/${OPENMPI_STD}"
elif [ "$MPIARG" == "openmpi_163" ]; then
    OPENMPI_STD_VER="1.6.3"
    OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"
    echo "Using OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    MPI="${SDPPATH}/${OPENMPI_STD}"
elif [ "$MPIARG" == "openmpi_165" ]; then
    OPENMPI_STD_VER="1.6.5"
    OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"
    echo "Using OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    MPI="${SDPPATH}/${OPENMPI_STD}"
elif [ "$MPIARG" == "openmpi_184" ]; then
    OPENMPI_STD_VER="1.8.4"
    OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"
    echo "Using OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    MPI="${SDPPATH}/${OPENMPI_STD}"
elif [ "$MPIARG" == "intelmpi" ]; then
    echo "Using Intel MPI"
    MPI="/prog/Intel/intel_mpi_4.0"
    INTELMPI=1
elif [ "$MPIARG" == "-help" -o "$MPIARG" == "--help" -o "$MPIARG" == "-h" ]; then
    echo "You must specify a correct argument for standard MPI version. Options are:"
    echo "  openmpi         - version ${OPENMPI_STD_VER} (default)"
    echo "  openmpi_132     - version 1.3.2 64-bit"
    echo "  openmpi_142     - version 1.4.2 64-bit"
    echo "  openmpi_163     - version 1.6.3 64-bit"
    echo "  openmpi_165     - version 1.6.5 64-bit"
    echo "  openmpi_184     - version 1.8.4 64-bit"
    echo "  mpich           - version 1.2.6 64-bit"
    echo "  mpich2          - version 1.3.2 64-bit"
    echo "  mpich_x86_64    - version 1.2.6 64-bit"
    echo "  intelmpi        - version 4.0.2 64-bit"
    echo
    echo "To use the SDP provided python set the PYTHON argument before sourcing: "
    echo "  PYTHON=\"3.6\" source /prog/sdpsoft/environment.sh"
    echo "      or"
    echo "  PYTHON=\"3.4\" source /prog/sdpsoft/environment.sh"
    echo "      or"
    echo "  PYTHON=\"3.3\" source /prog/sdpsoft/environment.sh"
    echo "      or"
    echo "  PYTHON=\"2.7\" source /prog/sdpsoft/environment.sh"
    echo "      or"
    echo "  PYTHON=\"2.6\" source /prog/sdpsoft/environment.sh"
    echo "      or"
    echo "  PYTHON=\"2.4\" source /prog/sdpsoft/environment.sh"
    echo
    echo "To use the SDP Provided ruby, set the RUBY argument before sourcing: "
    echo "  RUBY=\"1.9\" source /prog/sdpsoft/environment.sh"
    echo "      or"
    echo "  RUBY=\"2.0\" source /prog/sdpsoft/environment.sh"
    echo
    echo "To use the Intel compiler, set the COMPILER argument before sourcing: "
    echo "  COMPILER=\"intel\" source /prog/sdpsoft/environment.sh"
    echo
    EXIT=1
else
    echo "Using OpenMPI (${OPENMPI_STD}) as standard MPI interface (default)"
    echo "To use other MPI interfaces, add the argument \"-help\" to the environment file"
    MPI="${SDPPATH}/${OPENMPI_STD}"
fi

function enable_qt4() {
    if [ -z "$QT_VERSION" ]; then
        QT_VERSION="4.8.4"
        if [ -d ${SDPPATH}/qt-x11-$QT_VERSION ]; then
            export QT_VERSION=$QT_VERSION
        else
            # if we don't have v4.7.1, check for v4.7.1
            QT_VERSION="4.7.1"
            if [ -d ${SDPPATH}/qt-x11-$QT_VERSION ]; then
                export QT_VERSION=$QT_VERSION
            else
                # fallback to qt v3.3.5
                QT_VERSION="3.3.5"
            fi
        fi
    fi

    QT_PATH=$SDPPATH/qt-x11-$QT_VERSION
    if [ ! -d $QT_PATH ]; then
        echo "${QT_PATH} does not exist. Wrong QT version?"
        return
    fi

    export PATH=$QT_PATH/bin:$PATH
    export LD_LIBRARY_PATH=$QT_PATH/lib:$LD_LIBRARY_PATH
    export LIBRARY_PATH=$QT_PATH/lib:$LIBRARY_PATH
    export C_INCLUDE_PATH=$QT_PATH/include:$C_INCLUDE_PATH
    export CPLUS_INCLUDE_PATH=$QT_PATH/include:$CPLUS_INCLUDE_PATH

    echo "QT v$QT_VERSION enabled."    
}

function is_pythonpath_set() {
    test -n "$PYTHONPATH" && return 0 || return 1
}

if [ -n "$PYTHON" ]; then
    case "$PYTHON" in 
        2.4)
            echo "Python (2.4) SDP Team @ Statoil"
            export PATH=$SDPPATH/python2.4/bin:$PATH
            export LD_LIBRARY_PATH=$SDPPATH/python2.4/lib:$LD_LIBRARY_PATH
            P_PATH=""
            if ( ! is_pythonpath_set ) then
                P_PATH=${SDPPATH}/mercurial/lib64/python2.4/site-packages
            else
                if [[ ! "$PYTHONPATH" =~ ".*mercurial.*" ]]; then
                    P_PATH=${SDPPATH}/mercurial/lib64/python2.4/site-packages:$PYTHONPATH
                else
                    P_PATH=${PYTHONPATH//python2\.?/python2\.4}
                fi
            fi

            if [[ -n "$P_PATH" ]]; then
                export PYTHONPATH="$P_PATH"
            fi
        ;;
        2.6)
            echo "Python (2.6) SDP Team @ Statoil"
            export PATH=$SDPPATH/python2.6.7/bin:$PATH
            export LD_LIBRARY_PATH=$SDPPATH/python2.6.7/lib:$LD_LIBRARY_PATH
            P_PATH=""
            if ( ! is_pythonpath_set ) then
                P_PATH=${SDPPATH}/mercurial/lib64/python2.6/site-packages
            else
                if [[ ! "$PYTHONPATH" =~ ".*mercurial.*" ]]; then
                    P_PATH=${SDPPATH}/mercurial/lib64/python2.6/site-packages:$PYTHONPATH
                else
                    P_PATH=${PYTHONPATH//python2\.?/python2\.6}
                fi
            fi

            if [[ -n "$P_PATH" ]]; then
                export PYTHONPATH="$P_PATH"
            fi
        ;;
        2.7.6)
            echo "Python (2.7.6) SDP Team @ Statoil"
            export PATH=${SDPPATH}/python2.7.6/bin:$PATH
            export LD_LIBRARY_PATH=${SDPPATH}/python2.7.6/lib:$LD_LIBRARY_PATH
        ;;
        2.7.11)
            echo "Python (2.7.11) SDP Team @ Statoil"
            export PATH=${SDPPATH}/python2.7.11/bin:$PATH
            export LD_LIBRARY_PATH=${SDPPATH}/python2.7.11/lib:$LD_LIBRARY_PATH
        ;;
        2.7.13)
            echo "Python (2.7.13) SDP Team @ Statoil"
            export PATH=${SDPPATH}/python2.7.13/bin:$PATH
            export LD_LIBRARY_PATH=${SDPPATH}/python2.7.13/lib:$LD_LIBRARY_PATH
        ;;
        2.7)
            echo "Python (2.7.13) SDP Team @ Statoil"
            export PATH=${SDPPATH}/python2.7.13/bin:$PATH
            export LD_LIBRARY_PATH=${SDPPATH}/python2.7.13/lib:$LD_LIBRARY_PATH
        ;;
        3.3)
            echo "Python (3.3) SDP Team @ Statoil"
            export PATH=${SDPPATH}/python3.3.2/bin:$PATH
            export LD_LIBRARY_PATH=${SDPPATH}/python3.3.2/lib:$LD_LIBRARY_PATH
        ;;
        3.4)
            echo "Python (3.4) SDP Team @ Statoil"
            export PATH=${SDPPATH}/python3.4.2/bin:$PATH
            export LD_LIBRARY_PATH=${SDPPATH}/python3.4.2/lib:$LD_LIBRARY_PATH
        ;;
        3.6)
            echo "Python (3.6) SDP Team @ Statoil"
            export PATH=${SDPPATH}/python3.6.1/bin:$PATH
            export LD_LIBRARY_PATH=${SDPPATH}/python3.6.1/lib:$LD_LIBRARY_PATH
	    export QT_VERSION=5.4.2
        ;;
        *)
            echo "The following python version are available:"
            echo "PYTHON=\"3.6\""
            echo "PYTHON=\"3.4\""
            echo "PYTHON=\"3.3\""
            echo "PYTHON=\"2.7\""
            echo "PYTHON=\"2.6\""
            echo "PYTHON=\"2.4\""
            echo "    for example # PYTHON=\"2.7\" source /prog/sdpsoft/environment.sh"
            PYTHON="0"
        ;;
    esac
    export PYTHON=$PYTHON
fi

if [ -n "$RUBY" ]; then
    case "$RUBY" in
        1.8)
            echo "Ruby (1.8) SDP Team @ Statoil"
            RUBY_VERSION=$SDPPATH/ruby-1.8.7
            export PATH=$RUBY_VERSION/bin:$PATH
            export LD_LIBRARY_PATH=$RUBY_VERSION/lib:$LD_LIBRARY_PATH
            export GEM_HOME=$RUBY_VERSION/lib/ruby/gems/1.8
        ;;
        1.9)
            echo "Ruby (1.9) SDP Team @ Statoil"
            RUBY_VERSION=$SDPPATH/ruby-1.9.3
            export PATH=$RUBY_VERSION/bin:$PATH
            export LD_LIBRARY_PATH=$RUBY_VERSION/lib:$LD_LIBRARY_PATH
            export GEM_HOME=$RUBY_VERSION/lib/ruby/gems/1.9.1
        ;;
        2.0)
            echo "Ruby (2.0) SDP Team @ Statoil"
            RUBY_VERSION=$SDPPATH/ruby-2.0.0
            export PATH=$RUBY_VERSION/bin:$PATH
            export LD_LIBRARY_PATH=$RUBY_VERSION/lib:$LD_LIBRARY_PATH
            export GEM_HOME=$RUBY_VERSION/lib/ruby/gems/2.0.0
        ;;
        *)
            echo "The following ruby version are available:"
            echo "RUBY=\"1.9\" (recommended)"
            echo "RUBY=\"2.0\""
            echo "RUBY=\"1.8\" (old)"
            echo "    for example # RUBY=\"1.9\" source /prog/sdpsoft/environment.sh"
        ;;
    esac
else
    echo "Default Ruby (1.9) SDP Team @ Statoil"
    RUBY_VERSION=$SDPPATH/ruby-1.9.3
    export PATH=$RUBY_VERSION/bin:$PATH
    export LD_LIBRARY_PATH=$RUBY_VERSION/lib:$LD_LIBRARY_PATH
    export GEM_HOME=$RUBY_VERSION/lib/ruby/gems/1.9.1
fi

#Check to see if we should source anything
if [ $EXIT == 0 ]; then
    export SDPPATH=$SDPPATH
    
    if [ "$COMPILER" == "intel" ]; then
        echo "Intel compiler enabled"

        # Intel compilers (icc,icpc,ifort,..)
        if [ -e $INTELCCSTATOIL ]; then
        # Commented out by afel - 03/03/2014
            #source $INTELCCSTATOIL_OLD intel64
            #source $INTELFCSTATOIL_OLD intel64
            source $INTELCCSTATOIL_OLD intel64
            source $INTELCCSTATOIL intel64
        fi

        # Intel MKL library
        if [ -e $INTELMKLSTATOIL ]; then
        # Commented out by afel - 03/03/2014
            source $INTELMKLSTATOIL_OLD 
            source $INTELMKLSTATOIL intel64
        fi
    else
        echo "Intel compiler disabled (default)"

        # Even if the user is not using the Intel compilers, a lot of software
        # on sdpsoft still need libraries from Intel on LD_LIBRARY_PATH, so
        # adding it here
        export LD_LIBRARY_PATH=$INTELXESTATOIL/compiler/lib/intel64/:$INTELXESTATOIL/mkl/lib/intel64/:$LD_LIBRARY_PATH
    fi
    
    #environment for openmpi
    if [ $INTELMPI -eq 0 ]; then
        export OPAL_PREFIX=$MPI
    fi
    
    #environment for seismic unix
    export CWPROOT=$SDPPATH/SU    

    #environment for INTViewer
    export INTVIEWER_PATH=$SDPPATH/INTViewer
    export INTVIEWER_WORK_PATH=$SDPPATH/INTViewer
    export INTVIEWER_DATA_PATH=$SDPPATH/INTViewer
    export INTVIEWER_COLORMAP_PATH=$SDPPATH/INTViewer/ColorMaps

    #environment for madagascar
    if [ -n "$MADAGASCAR" ]; then
	    case "$MADAGASCAR" in
		1.4)
		    echo "Madagascar (1.4) SDPTeam @ Statoil"
		    MADAGASCAR_VERSION=$MADAGASCAR
		    ;;
		1.7)
		    echo "Madagascar (1.7) SDPTeam @ Statoil"
		    MADAGASCAR_VERSION=$MADAGASCAR
		    ;;
		*)
		    echo "The following Madagascar versions are available:"
		    echo "MADAGASCAR=\"1.7\" (default)"
		    echo "MADAGASCAR=\"1.4\""
		    echo "    for example # MADAGASCAR=\"1.7\" source /prog/sdpsoft/environment.sh"
		    ;;
	    esac
    else
	echo "Defaulting to Madagascar version 1.7"
	MADAGASCAR_VERSION=1.7	 
    fi
   
    if [[ -n "$MADAGASCAR_VERSION" ]]; then
	export RSFROOT=$SDPPATH/madagascar-$MADAGASCAR_VERSION
        
	if [[ ! "$PYTHONPATH" =~ "madagascar-$MADAGASCAR_VERSION" ]]; then
            source $RSFROOT/share/madagascar/etc/env.sh
        fi
    fi

    #SITISHT env variable for ScreenShot
    export SITISHT=$SDPPATH


    # If 'madagascar is not present in $PYTHONPATH, 
    # then add it to enable madagascar modules
    #if [[ ! "$PYTHONPATH" =~ ".*madagascar.*" ]]; then
	#	test -n "$PYTHONPATH" && P_RSF=${PYTHONPATH}:$RSFROOT/lib || P_RSF=$RSFROOT/lib
	#	export PYTHONPATH=$P_RSF
    #fi
    
    # export DATAPATH=/var/tmp

    #SVFTOOLS
    if [ ! -z $PATH ]; then
            if [ `expr "$PATH" : ".*$SDPPATH/bin"`  ]; then
                    export PATH="$SDPPATH/bin:$PATH"
            fi
    else
        export PATH="$SDPPATH/bin"
    fi
    
    if [ ! -z $LIBRARY_PATH ]; then
            if [ `expr "$LIBRARY_PATH" : ".*$SDPPATH"`  ]; then
                    export LIBRARY_PATH="$LIBRARY_PATH:$SDPPATH/lib"
            fi
    else 
        export LIBRARY_PATH="$SDPPATH/lib"
    fi
    if [ ! -z $LD_LIBRARY_PATH ]; then
            if [ `expr "$LD_LIBRARY_PATH" : ".*$SDPPATH"`  ]; then
                    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$SDPPATH/lib"
            fi
    else 
        export LD_LIBRARY_PATH="$SDPPATH/lib"
    fi
    if [ ! -z $PATH ]; then
            if [ `expr "$PATH" : ".*$SDPPATH"`  ]; then
                    export PATH="$PATH:$SDPPATH/bin"
            fi
    else 
        export PATH="$SDPPATH/bin"
    fi
    
    if [ ! -z $C_INCLUDE_PATH ]; then
        if [ `expr "$C_INCLUDE_PATH" : ".*$SDPPATH"`  ]; then
            export C_INCLUDE_PATH="$C_INCLUDE_PATH:$SDPPATH/include"
        fi
    else 
        export C_INCLUDE_PATH="$SDPPATH/include"
    fi
    
    if [ ! -z $CPLUS_INCLUDE_PATH ]; then
            if [ `expr "$CPLUS_INCLUDE_PATH" : ".*$SDPPATH"`  ]; then
                    export CPLUS_INCLUDE_PATH="$CPLUS_INCLUDE_PATH:$SDPPATH/include"
            fi
    else 
        export CPLUS_INCLUDE_PATH="$SDPPATH/include"
    fi

    if [ ! -z $FPATH ]; then
            if [ `expr "$FPATH" : ".*$SDPPATH"`  ]; then
                    export FPATH="$FPATH:$SDPPATH/include"
            fi
    else 
        export FPATH="$SDPPATH/include"
    fi

    #Setting MPI specific variables
    export MPI=$MPI
    if [ $INTELMPI -eq 1 ]; then
        # Intel MPI uses 'bin' for 32-bit, and 'bin64' for 64-bit
        export PATH=$MPI/bin64:$PATH
        export C_INCLUDE_PATH=$MPI/include64:$C_INCLUDE_PATH
        export FPATH=$MPI/include64:$FPATH
        export CPLUS_INCLUDE_PATH=$MPI/include64:$CPLUS_INCLUDE_PATH
        export LIBRARY_PATH=$MPI/lib64:$LIBRARY_PATH
        export LD_LIBRARY_PATH=$MPI/lib64:$LD_LIBRARY_PATH
    else
        # applies to mpich / openmpi
        export PATH=$MPI/bin:$PATH
        export C_INCLUDE_PATH=$MPI/include:$C_INCLUDE_PATH
        export FPATH=$MPI/include:$FPATH
        export CPLUS_INCLUDE_PATH=$MPI/include:$CPLUS_INCLUDE_PATH
        export LIBRARY_PATH=$MPI/lib:$LIBRARY_PATH
        export LD_LIBRARY_PATH=$MPI/lib:$LD_LIBRARY_PATH
    fi
fi #End exit test

#if [ -n "$QT_EXPERIMENTAL" ]; then
#    if [ "$QT_EXPERIMENTAL" -eq 1 ]; then
#        enable_qt4
#    fi
#else
#    if [ -n "$QT_VERSION" ]; then
#        enable_qt4
#    fi
#fi

enable_qt4

#SEPLIB
export SEPINC=$SDPPATH/include

#DELPHI
export DELPHIROOT=${SDPPATH}/delphi

# Temporary java implementation with Java3D builtin for 64-bit linux
export JAVA_HOME=${SDPPATH}/java
export PATH=$JAVA_HOME/bin:$PATH
export LD_LIBRARY_PATH=$JAVA_HOME/jre/lib/amd64:$LD_LIBRARY_PATH

if [ -e "/prog/promax/SSclient" ]; then
    alias SSclient="/prog/promax/SSclient"
elif [ -e "/prog/promax_top/script/SSclient" ]; then
    alias SSclient="/prog/promax_top/script/SSclient"
fi

# golang
if [ -x "/prog/sdpsoft/go-1.7.3/bin/go" ]; then
    export GOROOT="/prog/sdpsoft/go-1.7.3"
    export PATH="/prog/sdpsoft/go-1.7.3/bin:$PATH"
fi

# verify that it is an interactive session
if [ $INTERACTIVE -eq 1 -a -n "$BASH_VERSION" ]; then
    # bash auto-completion for mercurial
    if [ -x ${SDPPATH}/mercural/bash_completion ]; then
        source $SDPPATH/mercurial/bash_completion
    fi

    # bash auto-completion for git
    if [ -x ${SDPPATH}/git/git-completion.bash ]; then
        source $SDPPATH/git/git-completion.bash
    fi
    
    # bash auto-completion for git-extra
    if [ -x ${SDPPATH}/git-extras/etc/bash_completion.d/git-extras ]; then
        source $SDPPATH/git-extras/etc/bash_completion.d/git-extras
    fi
fi
