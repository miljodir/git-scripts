#!/bin/csh -x

set SDPPATH="/prog/sdpsoft"

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
grep -q "^$USER " $SDPPATH/.user.log
if ( "$?" != "0" ) then
    echo "$USER " >> $SDPPATH/.user.log
endif

################## END OF DEPRECATION #################

if (! $?LANG ) setenv LANG "en_US.UTF8"
set MPIARG=$1

# Commented out by afel - 03/03/2014
#set INTELCCSTATOIL="/prog/Intel/studioxe2013/bin/compilervars.csh"
#set INTELCCSTATOIL_OLD="/prog/Intel/studioxe/bin/compilervars.csh"
#set INTELFCSTATOIL_OLD="/prog/Intel/intel_fc_11/bin/ifortvars.csh"

set INTELXESTATOIL="/prog/Intel/studioxe/composer_xe_2011_sp1.11.339"
set INTELCCSTATOIL="/prog/Intel/studioxe/bin/compilervars.csh"
set INTELCCSTATOIL_OLD="/prog/Intel/intel_cc_11/bin/iccvars.csh"
#set INTELFCSTATOIL_OLD="/prog/Intel/intel_fc_11/bin/ifortvars.csh"

# Intel MKL Kernel
# Commented out by afel - 03/03/2014
#set INTELMKLSTATOIL="/prog/Intel/studioxe2013/mkl/bin/mklvars.csh"
#set INTELMKLSTATOIL_OLD="/prog/Intel/studioxe/mkl/bin/mklvars.csh"

set INTELMKLSTATOIL="/prog/Intel/studioxe/mkl/bin/mklvars.csh"
set INTELMKLSTATOIL_OLD="/prog/Intel/mkl10cluster/tools/environment/mklvarsem64t.csh" 

# Open-MPI
set OPENMPI_STD_VER="1.8.4"
set OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"

# Intel MPI
set INTELMPI=0

if ( $MPIARG == "" ) then
    echo "Using OpenMPI as standard MPI interface (default)"
    echo "To use other MPI interfaces, add the argument '-help' to the environment file"
    set MPI="${SDPPATH}/${OPENMPI_STD}"
else if ( $MPIARG == "mpich_x86_64" || $MPIARG == "mpich" ) then
    set MPI="${SDPPATH}/mpich-1.2.6_x86_64"
    echo "Using MPICH 64-bit version as standard MPI interface"
else if ( $MPIARG == "mpich2" ) then
    set MPI="${SDPPATH}/mpich2-1.3.2"
    echo "Using MPICH2 v1.3.2 as standard MPI interface"
else if ( $MPIARG == "openmpi" ) then
    echo "Using OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    set MPI="${SDPPATH}/${OPENMPI_STD}"
else if ( $MPIARG == "openmpi_132" ) then
    set OPENMPI_STD_VER="1.3.2"
    set OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"
    echo "Using EXPERIMENTAL OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    set MPI="/usr/lib64/openmpi/1.3.2-gcc"
    setenv OMPI_MCA_btl "tcp,self" # to use only ethernet(tcp) and loopback
else if ( $MPIARG == "openmpi_142" ) then
    set OPENMPI_STD_VER="1.4.2"
    set OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"
    echo "Using OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    set MPI="${SDPPATH}/${OPENMPI_STD}"
else if ( $MPIARG == "openmpi_163" ) then
    set OPENMPI_STD_VER="1.6.3"
    set OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"
    echo "Using OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    set MPI="${SDPPATH}/${OPENMPI_STD}"
else if ( $MPIARG == "openmpi_165" ) then
    set OPENMPI_STD_VER="1.6.5"
    set OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"
    echo "Using OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    set MPI="${SDPPATH}/${OPENMPI_STD}"
else if ( $MPIARG == "openmpi_184" ) then
    set OPENMPI_STD_VER="1.8.4"
    set OPENMPI_STD="openmpi-${OPENMPI_STD_VER}"
    echo "Using OpenMPI (${OPENMPI_STD_VER}) as standard MPI interface"
    set MPI="${SDPPATH}/${OPENMPI_STD}"
else if ( "$MPIARG" == "intelmpi" ) then
    echo "Using Intel MPI"
    set MPI="/prog/Intel/intel_mpi_4.0"
    set INTELMPI=1
else if ( $MPIARG == "-help" || $MPIARG == "--help" || $MPIARG == "-h" ) then
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
    echo "  set PYTHON='3.6'; source /prog/sdpsoft/environment.csh"
    echo "      or"
    echo "  set PYTHON='3.4'; source /prog/sdpsoft/environment.csh"
    echo "      or"
    echo "  set PYTHON='3.3'; source /prog/sdpsoft/environment.csh"
    echo "      or"
    echo "  set PYTHON='2.7'; source /prog/sdpsoft/environment.csh"
    echo "      or"
    echo "  set PYTHON='2.6'; source /prog/sdpsoft/environment.csh"
    echo "      or"
    echo "  set PYTHON='2.4'; source /prog/sdpsoft/environment.csh"
    echo
    echo "To use the SDP provided ruby set the RUBY argument before sourcing: "
    echo "  set RUBY='1.9'; source /prog/sdpsoft/environment.csh"
    echo "      or"
    echo "  set RUBY='2.0'; source /prog/sdpsoft/environment.csh"
    echo
    echo "To use the Intel compiler, set the COMPILER argument before sourcing: "
    echo "  set COMPILER='intel' source /prog/sdpsoft/environment.csh"
    exit(1)
else
    echo "Using OpenMPI as standard MPI interface (default)"
    echo "To use other MPI interfaces, add the argument '-help' to the environment file"
    set MPI="${SDPPATH}/${OPENMPI_STD}"
endif


if ($?PYTHON) then
    switch ($PYTHON)
        case "2.4":
            echo "Python (2.4) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/python2.4/bin:${PATH}"
            if(! $?LD_LIBRARY_PATH) then
                setenv LD_LIBRARY_PATH "${SDPPATH}/python2.4/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/python2.4/lib:${LD_LIBRARY_PATH}"
            endif
            if ( ! $?PYTHONPATH) then
                setenv PYTHONPATH "${SDPPATH}/mercurial/lib64/python2.4/site-packages"
            else
                if ( "$PYTHONPATH" !~ *mercurial* ) then
                    setenv PYTHONPATH "${SDPPATH}/mercurial/lib64/python2.4/site-packages:${PYTHONPATH}"
                else
                    set P_PATH=`echo ${PYTHONPATH} | sed "s/python[0-9].[0-9]/python2.4/g"`
                    setenv PYTHONPATH ${P_PATH}
                endif
            endif
            breaksw
        case "2.6":
            echo "Python (2.6) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/python2.6.7/bin:${PATH}"
            if(! $?LD_LIBRARY_PATH) then
                setenv LD_LIBRARY_PATH "${SDPPATH}/python2.6.7/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/python2.6.7/lib:${LD_LIBRARY_PATH}"
            endif
            if ( ! $?PYTHONPATH) then
                setenv PYTHONPATH "${SDPPATH}/mercurial/lib64/python2.6/site-packages"
            else
                if ( "$PYTHONPATH" !~ *mercurial* ) then
                    setenv PYTHONPATH "${SDPPATH}/mercurial/lib64/python2.6/site-packages:${PYTHONPATH}"
                else
                    set P_PATH=`echo ${PYTHONPATH} | sed "s/python[0-9.[0-9]/python2.6/g"`
                    setenv PYTHONPATH ${P_PATH}
                endif
            endif
            breaksw
        case "2.7.6":
            echo "Python (2.7.6) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/python2.7.6/bin:${PATH}"
            if(! $?LD_LIBRARY_PATH) then
                setenv LD_LIBRARY_PATH "${SDPPATH}/python2.7.6/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/python2.7.6/lib:${LD_LIBRARY_PATH}"
            endif
            breaksw
        case "2.7.11":
            echo "Python (2.7.11) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/python2.7.11/bin:${PATH}"
            if(! $?LD_LIBRARY_PATH) then
                setenv LD_LIBRARY_PATH "${SDPPATH}/python2.7.11/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/python2.7.11/lib:${LD_LIBRARY_PATH}"
            endif
            breaksw
        case "2.7.13":
            echo "Python (2.7.13) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/python2.7.13/bin:${PATH}"
            if(! $?LD_LIBRARY_PATH) then
                setenv LD_LIBRARY_PATH "${SDPPATH}/python2.7.13/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/python2.7.13/lib:${LD_LIBRARY_PATH}"
            endif
            breaksw
        case "2.7":
            echo "Python (2.7.13) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/python2.7.13/bin:${PATH}"
            if(! $?LD_LIBRARY_PATH) then
            setenv LD_LIBRARY_PATH "${SDPPATH}/python2.7.13/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/python2.7.13/lib:${LD_LIBRARY_PATH}"
            endif
            breaksw
        case "3.3":
            echo "Python (3.3) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/python3.3.2/bin:${PATH}"
            if(! $?LD_LIBRARY_PATH) then
                setenv LD_LIBRARY_PATH "${SDPPATH}/python3.3.2/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/python3.3.2/lib:${LD_LIBRARY_PATH}"
            endif
            breaksw
        case "3.4":
            echo "Python (3.4) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/python3.4.2/bin:${PATH}"
            if(! $?LD_LIBRARY_PATH) then
                setenv LD_LIBRARY_PATH "${SDPPATH}/python3.4.2/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/python3.4.2/lib:${LD_LIBRARY_PATH}"
            endif
            breaksw
        case "3.6":
            echo "Python (3.6) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/python3.6.1/bin:${PATH}"
            setenv QT_VERSION "5.4.2"
            if(! $?LD_LIBRARY_PATH) then
                setenv LD_LIBRARY_PATH "${SDPPATH}/python3.6.1/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/python3.6.1/lib:${LD_LIBRARY_PATH}"
            endif
            breaksw
        default:
            echo "The following python versions are available:"
            echo "PYTHON=3.6"
            echo "PYTHON=3.4"
            echo "PYTHON=3.3"
            echo "PYTHON=2.7"
            echo "PYTHON=2.6"
            echo "PYTHON=2.4"
            echo "    for example # set PYTHON='2.7'; source /prog/sdpsoft/environment.csh"
            #set PYTHON="0"
    endsw
    setenv PYTHON
endif

if ($?RUBY) then
    switch ($RUBY)
        case "1.8":
            echo "Ruby (1.8) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/ruby-1.8.7/bin:${PATH}"
            if(! $?LD_LIBRARY_PATH) then
                setenv LD_LIBRARY_PATH "${SDPPATH}/ruby-1.8.7/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/ruby-1.8.7/lib:${LD_LIBRARY_PATH}"
            endif
            setenv GEM_HOME "${SDPPATH}/ruby-1.8.7/lib/ruby/gems/1.8"
            breaksw
        case "1.9":
            echo "Ruby (1.9) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/ruby-1.9.3/bin:${PATH}"
            if(! $?LD_LIBRARY_PATH) then
                setenv LD_LIBRARY_PATH "${SDPPATH}/ruby-1.9.3/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/ruby-1.9.3/lib:${LD_LIBRARY_PATH}"
            endif
            setenv GEM_HOME "${SDPPATH}/ruby-1.9.3/lib/ruby/gems/1.9.1"
            breaksw
        case "2.0":
            echo "Ruby (2.0) SDP Team @ Statoil"
            setenv PATH "${SDPPATH}/ruby-2.0.0/bin:${PATH}"
            if(! $?LD_LIBRARY_PATH) then
                setenv LD_LIBRARY_PATH "${SDPPATH}/ruby-2.0.0/lib"
            else
                setenv LD_LIBRARY_PATH "${SDPPATH}/ruby-2.0.0/lib:${LD_LIBRARY_PATH}"
            endif
            setenv GEM_HOME "${SDPPATH}/ruby-2.0.0/lib/ruby/gems/2.0.0"
            breaksw
        default:
            echo "The following ruby versions are available:"
            echo "RUBY=1.8"
            echo "RUBY=1.9"
            echo "RUBY=2.0"
            echo "    for example # set RUBY='1.9'; source /prog/sdpsoft/environment.csh"
    endsw
else
    echo "Default Ruby (1.9) SDP Team @ Statoil"
    setenv PATH "${SDPPATH}/ruby-1.9.3/bin:${PATH}"
    if(! $?LD_LIBRARY_PATH) then
        setenv LD_LIBRARY_PATH "${SDPPATH}/ruby-1.9.3/lib"
    else
        setenv LD_LIBRARY_PATH "${SDPPATH}/ruby-1.9.3/lib:${LD_LIBRARY_PATH}"
    endif
    setenv GEM_HOME "${SDPPATH}/ruby-1.9.3/lib/ruby/gems/1.9.1"
endif

set_qt:
    if ($?QT_SET) then
        if (! $?QT_VERSION ) then
            setenv QT_VERSION "4.8.4"
        endif

        set QT_PATH="${SDPPATH}/qt-x11-${QT_VERSION}"
        setenv PATH $QT_PATH/bin:$PATH
        if (! $?LD_LIBRARY_PATH) then
            setenv LD_LIBRARY_PATH $QT_PATH/lib
        else
            setenv LD_LIBRARY_PATH $QT_PATH/lib:$LD_LIBRARY_PATH
        endif

        if (! $?C_INCLUDE_PATH) then
            setenv C_INCLUDE_PATH $QT_PATH/include
        else
            setenv C_INCLUDE_PATH $QT_PATH/include:$C_INCLUDE_PATH
        endif

        if (! $?CPLUS_INCLUDE_PATH) then
            setenv CPLUS_INCLUDE_PATH $QT_PATH/include
        else
            setenv CPLUS_INCLUDE_PATH $QT_PATH/include:$CPLUS_INCLUDE_PATH
        endif


        echo "QT v${QT_VERSION} enabled."
    endif

if (! $?QT_PATH) then
    set QT_SET="1"
    goto set_qt
endif

    
setenv SDPPATH ${SDPPATH}

if ( ${INTELMPI} == 0 ) then
    #environment for openmpi
    setenv OPAL_PREFIX ${MPI}
endif

#environment for seismic unix
setenv CWPROOT ${SDPPATH}/SU

#environment for INTViewer
setenv INTVIEWER_PATH ${SDPPATH}/INTViewer
setenv INTVIEWER_WORK_PATH ${SDPPATH}/INTViewer
setenv INTVIEWER_DATA_PATH ${SDPPATH}/INTViewer
setenv INTVIEWER_COLORMAP_PATH ${SDPPATH}/INTViewer/ColorMaps

#environment for madagascar

if ( $?MADAGASCAR ) then
    switch ($MADAGASCAR)
	case "1.4":
	    echo "Madagascar (1.4) SDPTeam @ Statoil"
	    setenv MADAGASCAR_VERSION "1.4"
	    breaksw
	case "1.7":
	    echo "Madagascar (1.7) SDPTeam @ Statoil"
	    setenv MADAGASCAR_VERSION "1.7"
	    breaksw
	default:
	    echo "The following Madagascar versions are available:"
	    echo "MADAGASCAR=\"1.7\" (default)"
	    echo "MADAGASCAR=\"1.4\""
	    echo "    for example # set MADAGASCAR=\"1.7\"; source /prog/sdpsoft/environment.sh"
	    breaksw
    endsw
else
    echo "Defaulting to Madagascar version 1.7"
    setenv MADAGASCAR_VERSION "1.7"
endif

if ( $?MADAGASCAR_VERSION ) then
    setenv RSFROOT "${SDPPATH}/madagascar-${MADAGASCAR_VERSION}"

    if (! $?PYTHONPATH ) then
        source $RSFROOT/share/madagascar/etc/env.csh
    else if ( "${PYTHONPATH}" !~ "madagascar-$MADAGASCAR_VERSION" ) then
        source $RSFROOT/share/madagascar/etc/env.csh
    endif
endif

# setenv RSFROOT ${SDPPATH}/madagascar

#SITISHT env variable for ScreenShot
setenv SITISHT ${SDPPATH}

# If 'madagascar is not present in $PYTHONPATH, 
# then add it to enable madagascar modules
# if (! $?PYTHONPATH ) then
#     source $RSFROOT/share/madagascar/etc/env.csh
# else if ( "${PYTHONPATH}" !~ *madagascar* ) then
#     source $RSFROOT/share/madagascar/etc/env.csh
# endif


if ( $?COMPILER ) then
    if ( $COMPILER == "intel" ) then
        set INTEL_COMPILER=1
    endif
endif

if ( $?INTEL_COMPILER ) then
    echo "Intel compiler enabled"

    # Intel compiler (icc,icpc,ifort,..)
    if( -e $INTELCCSTATOIL ) then
        source $INTELCCSTATOIL_OLD intel64
        source $INTELCCSTATOIL intel64

    endif

    # Intel MKL Library
    if ( -e $INTELMKLSTATOIL ) then
        # MKLROOT may already have been set by INTELCCSTATOIL.
        # We want to use the INTELMKLSTATOIL root instead, so
        # we unset MKLROOT before sourcing environment files.
        # Ref. Trac #285.
        if ( -e $MKLROOT ) then 
            unset MKLROOT
        endif
        source $INTELMKLSTATOIL_OLD
        source $INTELMKLSTATOIL intel64
    endif
else
    echo "Intel compiler disabled (default)"

    # Even if the user is not using the Intel compilers, a lot of software 
    # on sdpsoft still need libraries from Intel on LD_LIBRARY_PATH, so 
    # adding it here
    setenv LD_LIBRARY_PATH "$INTELXESTATOIL/compiler/lib/intel64/:$INTELXESTATOIL/mkl/lib/intel64/:$LD_LIBRARY_PATH"
endif


#SVFTOOLS
if ($?PATH) then
        if ( "${PATH}" !~ *$SDPPATH/bin* ) then
                setenv PATH "${SDPPATH}/bin:${PATH}"
        endif
else
    setenv PATH "${SDPPATH}/bin"
endif

if ($?LIBRARY_PATH) then
        if ( "${LIBRARY_PATH}" !~ *$SDPPATH* ) then
                setenv LIBRARY_PATH "${LIBRARY_PATH}:${SDPPATH}/lib"
        endif
else 
    setenv LIBRARY_PATH "${SDPPATH}/lib"
endif
if ($?LD_LIBRARY_PATH) then
        if ( "${LD_LIBRARY_PATH}" !~ *$SDPPATH/lib* ) then
                setenv LD_LIBRARY_PATH "${LD_LIBRARY_PATH}:${SDPPATH}/lib"
        endif
else 
    setenv LD_LIBRARY_PATH "${SDPPATH}/lib"
endif
if ($?PATH) then
        if ( "${PATH}" !~ *$SDPPATH* ) then
                setenv PATH "${PATH}:${SDPPATH}/bin"
        endif
else 
    setenv PATH "${SDPPATH}/bin"
endif

if ($?C_INCLUDE_PATH) then
        if ( "${C_INCLUDE_PATH}" !~ *${SDPPATH}/include* ) then
                setenv C_INCLUDE_PATH "${C_INCLUDE_PATH}:${SDPPATH}/include"
        endif
else 
    setenv C_INCLUDE_PATH "${SDPPATH}/include"
endif

if ($?CPLUS_INCLUDE_PATH) then
        if ( "${CPLUS_INCLUDE_PATH}" !~ *${SDPPATH}/include* ) then
                setenv CPLUS_INCLUDE_PATH "${CPLUS_INCLUDE_PATH}:${SDPPATH}/include"
        endif
else 
    setenv CPLUS_INCLUDE_PATH "${SDPPATH}/include"
endif

if ($?FPATH) then
        if ( "${FPATH}" !~ *$SDPPATH* ) then
                setenv FPATH "${FPATH}:${SDPPATH}/include"
        endif
else 
    setenv FPATH "${SDPPATH}/include"
endif

if ( ${INTELMPI} == 1 ) then
    #Setting Intel MPI specific variables
    setenv MPI ${MPI}
    setenv PATH ${MPI}/bin64:${PATH}
    setenv C_INCLUDE_PATH ${MPI}/include64:${C_INCLUDE_PATH}
    setenv FPATH ${MPI}/include64:${FPATH}
    setenv CPLUS_INCLUDE_PATH ${MPI}/include64:${CPLUS_INCLUDE_PATH}
    setenv LIBRARY_PATH ${MPI}/lib64:${LIBRARY_PATH}
    setenv LD_LIBRARY_PATH ${MPI}/lib64:${LD_LIBRARY_PATH}
else
    #Setting MPI specific variables
    setenv MPI ${MPI}
    setenv PATH ${MPI}/bin:${PATH}
    setenv C_INCLUDE_PATH ${MPI}/include:${C_INCLUDE_PATH}
    setenv FPATH ${MPI}/include:${FPATH}
    setenv CPLUS_INCLUDE_PATH ${MPI}/include:${CPLUS_INCLUDE_PATH}
    setenv LIBRARY_PATH ${MPI}/lib:${LIBRARY_PATH}
    setenv LD_LIBRARY_PATH ${MPI}/lib:${LD_LIBRARY_PATH}
endif


#SEPLIB
setenv SEPINC ${SDPPATH}/include

#DELPHI
setenv DELPHIROOT ${SDPPATH}/delphi

if (-e "/prog/promax/SSclient") then
    alias SSclient "/prog/promax/SSclient"
else if(-e "/prog/promax_top/script/SSclient") then
    alias SSclient "/prog/promax_top/script/SSclient"
endif

# Temporary java implementation with Java3D builtin for 64-bit linux
setenv JAVA_HOME ${SDPPATH}/java
setenv PATH ${JAVA_HOME}/bin:${PATH}
setenv LD_LIBRARY_PATH $JAVA_HOME/jre/lib/amd64:${LD_LIBRARY_PATH}

setenv GEM_HOME ${SDPPATH}/ruby/lib/ruby/gems/1.8

# golang
if (-x "/prog/sdpsoft/go-1.7.3/bin/go") then
    setenv GOROOT "/prog/sdpsoft/go-1.7.3"
    setenv PATH "/prog/sdpsoft/go-1.7.3/bin:$PATH"
endif

# Remove duplicates from variables
setenv LIB `/prog/sdpsoft/dedup_env.py LIB`
setenv PATH `/prog/sdpsoft/dedup_env.py PATH`
setenv CPATH `/prog/sdpsoft/dedup_env.py CPATH`
setenv FPATH `/prog/sdpsoft/dedup_env.py FPATH`
setenv MANPATH `/prog/sdpsoft/dedup_env.py MANPATH`
setenv NLSPATH `/prog/sdpsoft/dedup_env.py NLSPATH`
setenv INTEL_LICENSE_FILE `/prog/sdpsoft/dedup_env.py INTEL_LICENSE_FILE`
setenv INCLUDE `/prog/sdpsoft/dedup_env.py INCLUDE`
setenv INCLUDE_PATH `/prog/sdpsoft/dedup_env.py INCLUDE_PATH`
setenv C_INCLUDE_PATH `/prog/sdpsoft/dedup_env.py C_INCLUDE_PATH`
setenv CPLUS_INCLUDE_PATH `/prog/sdpsoft/dedup_env.py CPLUS_INCLUDE_PATH`
setenv LIBRARY_PATH `/prog/sdpsoft/dedup_env.py LIBRARY_PATH`
setenv LD_LIBRARY_PATH `/prog/sdpsoft/dedup_env.py LD_LIBRARY_PATH`
setenv DYLD_LIBRARY_PATH `/prog/sdpsoft/dedup_env.py DYLD_LIBRARY_PATH`

