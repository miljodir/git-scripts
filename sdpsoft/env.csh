#!/usr/bin/env csh

# Color and text manipulation variables
# Using these colors causes some issues with the terminal. We've gotten complaints, nulling them out
#set COLOR_NONE="\033[00m"
#set COLOR_RED="\033[1;31m"
#set COLOR_GREEN="\033[0;32m"
#set COLOR_YELLOW="\033[1;33m"
#set COLOR_BLUE="\033[1;34m"
#set COLOR_MAGENTA="\033[1;35m"
#set COLOR_PURPLE="\033[01;35m"
#set COLOR_CYAN="\033[1;36m"
#set COLOR_WHITE="\033[0;37m"
#set TEXT_BOLD="\033[1m"
#set TEXT_UNDERLINE="\033[4m"
#set TEXT_NO_UNDERLINE="\033[24m"

set COLOR_NONE=""
set COLOR_RED=""
set COLOR_GREEN=""
set COLOR_YELLOW=""
set COLOR_BLUE=""
set COLOR_MAGENTA=""
set COLOR_PURPLE=""
set COLOR_CYAN=""
set COLOR_WHITE=""
set TEXT_BOLD=""
set TEXT_UNDERLINE=""
set TEXT_NO_UNDERLINE=""


set SDPSOFT_PATH="/prog/sdpsoft"
# SDPSOFT_PATH_REAL is used for those cases where you set SDPSOFT_PATH to "/data/sdpsoft" to test some local changes
# but the test requires that you use something at the REAL SDPSoft location (like testing logging entries)
set SDPSOFT_PATH_REAL="/prog/sdpsoft"

if (! $?LANG ) setenv LANG "en_US.UTF8"

if ( "$1" == "help" || "$1" == "--help" || "$1" == "menu" || "$1" == "--menu" ) then
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
  printf "\n    source /prog/sdpsoft/env.csh --search python\n"
  printf "${COLOR_CYAN}"
  printf "\n  Sourcing software:\n"
  printf "${COLOR_NONE}"
  printf '\n    setenv GCC_VERSION \"4.9.4\"\n'
  printf '    setenv QT_VERSION \"5.4.2\"\n'
  printf '    setenv PYTHON_VERSION \"latest\"\n'
  printf '    source /prog/sdpsoft/env.csh\n'
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
  printf '\n'
else if ( "$1" == "--search" ) then
  if ( "$2" == "" ) then
    printf "\n${COLOR_YELLOW}No search term defined\! Please define a search term${COLOR_NONE}\n\n"
    source $SDPSOFT_PATH/env.csh --help
  else
    set search_term=$2
    set software_in_sdpsoft=`find ${SDPSOFT_PATH} -maxdepth 1 -type d -iname "*$search_term*" | sort -fV | cut -d"/" -f4- | grep -v "^\." | grep "[a-zA-Z0-9\_\-].*[0-9].*"`

    if ( "$software_in_sdpsoft" != "" ) then
      printf "\n${COLOR_GREEN}Search results:${COLOR_NONE}\n\n"
      foreach software ($software_in_sdpsoft)
        printf " - $software\n"
      end
      printf "\n"
    else
      printf "\n${COLOR_YELLOW}Unable to find ${TEXT_UNDERLINE}$search_term${TEXT_NO_UNDERLINE} in SDPSoft${COLOR_NONE}\n\n"
    endif
  endif

else if ( "$1" == "--source" ) then
    set requested_version="$2"
    set available_versions_string="$3"
    set software_name="$4"
    set silent_output="$5"
    set i = 0
    set available_versions =
    foreach version ($available_versions_string)
      set available_versions = ( $available_versions $version )
      @ i++
    end
    if ( "$requested_version" == "latest" ) then
      set requested_version="$available_versions[$#available_versions]"
    endif

    foreach version ($available_versions)
      if ( "$version" == "$requested_version" ) then

        if ( -d "${SDPSOFT_PATH}/${software_name}_${requested_version}" ) then
            set separator="_"
        else if ( -d "${SDPSOFT_PATH}/${software_name}-${requested_version}" ) then
            set separator="-"
        else if ( -d "${SDPSOFT_PATH}/${software_name}${requested_version}" ) then
            set separator=""
        else
            set separator="-"
        endif

        set software_path="$SDPSOFT_PATH/${software_name}${separator}${requested_version}"
        if ( -d "${software_path}/bin" ) then
          setenv PATH "${software_path}/bin:$PATH"
        endif

        if ( -d "${software_path}/lib" ) then
          if ( "$?LIBRARY_PATH" ) then
            setenv LIBRARY_PATH "${software_path}/lib:$LIBRARY_PATH"
          else
            setenv LIBRARY_PATH "${software_path}/lib"
          endif
        endif

        if ( -d "${software_path}/lib64" ) then
          if ( "$?LIBRARY_PATH" ) then
            setenv LIBRARY_PATH "${software_path}/lib:$LIBRARY_PATH"
          else
            setenv LIBRARY_PATH "${software_path}/lib"
          endif
        endif

        if ( -d "${software_path}/lib" ) then
          if ( "$?LD_LIBRARY_PATH" ) then
            setenv LD_LIBRARY_PATH "${software_path}/lib:$LD_LIBRARY_PATH"
          else
            setenv LD_LIBRARY_PATH "${software_path}/lib"
          endif
        endif

        if ( -d "$software_path/lib64" ) then
          if ( "$?LD_LIBRARY_PATH" ) then
            setenv LD_LIBRARY_PATH "$software_path/lib64:$LD_LIBRARY_PATH"
          else
            setenv LD_LIBRARY_PATH "$software_path/lib64"
          endif
        endif

        if ( -d "$software_path/include" ) then
          if ( "$?CPATH" ) then
            setenv CPATH "$software_path/include:$CPATH"
          else
            setenv CPATH "$software_path/include"
          endif
        endif

        if ( -d "$software_path/include" ) then
          if ( "$?C_INCLUDE_PATH" ) then
            setenv C_INCLUDE_PATH "$software_path/include:$C_INCLUDE_PATH"
          else
            setenv C_INCLUDE_PATH "$software_path/include"
          endif
        endif

        if ( -d "$software_path/include" ) then
          if ( "$?CPLUS_INCLUDE_PATH" ) then
            setenv CPLUS_INCLUDE_PATH "$software_path/include:$CPLUS_INCLUDE_PATH"
          else
            setenv CPLUS_INCLUDE_PATH "$software_path/include"
          endif
        endif

        if ( -d "$software_path/include" ) then
          if ( "$?OBJC_INCLUDE_PATH" ) then
            setenv OBJC_INCLUDE_PATH "$software_path/include:$OBJC_INCLUDE_PATH"
          else
            setenv OBJC_INCLUDE_PATH "$software_path/include"
          endif
        endif

        if ( -d "$software_path/man" ) then
          if ( "$?MANPATH" ) then
            setenv MANPATH "$software_path/man:$MANPATH"
          else
            setenv MANPATH "$software_path/man"
          endif
        endif

        if ( "$silent_output" == "False" ) then
          printf "${COLOR_GREEN}"
          printf "$software_name $requested_version\n"
          printf "${COLOR_NONE}"
        endif
        set timestamp=`date -u +"%F_%H:%M:%S"`
        # Using sed -i causes a problem with writing temporary sed-file to /prog/sdpsoft
        # which normal users do not have access to, resulting in failed Jenkins builds etc..
        # Therefore, setting temp to the sed'ed output and use that to populate .software.log became
        # the working solution
        set temp=`sed "/^${software_name}${separator}${requested_version}@/d" $SDPSOFT_PATH_REAL/.software.log`
        # The noclobber setting prevents output redirection from overwriting existing files. Needs to be unset
        # ref: https://www2.cs.duke.edu/csl/docs/unix_course/intro-61.html
        unset noclobber
        echo "${temp}" | tr " " "\n" > $SDPSOFT_PATH_REAL/.software.log
        echo "${software_name}${separator}${requested_version}@$timestamp" >> $SDPSOFT_PATH_REAL/.software.log
        exit 0
      endif
    end
    printf "${COLOR_YELLOW}"
    printf "$software_name $requested_version not found\!\n"
    printf "Available versions for $software_name\n"
    foreach version ($available_versions)
        echo $version
    end
    printf "${COLOR_NONE}"
    exit 2

else

  if ( "$1" == "--silent" ) then
    set SILENT_OUTPUT=True
  else
    set SILENT_OUTPUT=False
  endif
  ################# LEGACY STUFF START ##############################
# Enable legacy stuff which were defaults in the old source scripts
#  INTELXESTATOIL="/prog/Intel/studioxe/composer_xe_2011_sp1.11.339"
#  INTELCCSTATOIL="/prog/Intel/studioxe/bin/compilervars.sh"
#  INTELCCSTATOIL_OLD="/prog/Intel/intel_cc_11/bin/iccvars.sh"
#  INTELMKLSTATOIL="/prog/Intel/studioxe/mkl/bin/mklvars.sh"
#  INTELMKLSTATOIL_OLD="/prog/Intel/mkl10cluster/tools/environment/mklvarsem64t.sh"

# Currently, no usage information for intel_mpi in the help menu provided. Waiting to see how much it is used first.

  if ( "$?INTEL_MPI" ) then
    if ( "$INTEL_MPI" == "yes" ) then
      if ( "$?OPENMPI_VERSION" ) then
        printf "${COLOR_RED}"
        printf "You are trying to source with both intelmpi and openmpi\n"
        printf "Aborting to avoid unexpected behaviour\n"
        printf "${COLOR_NONE}"
        exit 2
      else
        setenv MPI "/prog/Intel/intel_mpi_4.1"
        setenv PATH "$MPI/bin64:$PATH"
        setenv CPATH "$MPI/include64:$CPATH"
        setenv C_INCLUDE_PATH "$MPI/include64:$C_INCLUDE_PATH"
        setenv CPLUS_INCLUDE_PATH "$MPI/include64:$CPLUS_INCLUDE_PATH"
        setenv OBJC_INCLUDE_PATH "$MPI/include64:$OBJC_INCLUDE_PATH"
        setenv FPATH "$MPI/include64:$FPATH"
        setenv LIBRARY_PATH "$MPI/lib64:$LIBRARY_PATH"
        setenv LD_LIBRARY_PATH "$MPI/lib64:$LD_LIBRARY_PATH"
        printf "${COLOR_GREEN}${MPI}${COLOR_NONE}\n"
      endif
    endif
  endif
  ################# LEGACY STUFF END ##############################


  if ( "$?ARPACK_NG_VERSION" ) then
    set ARPACK_NG_VERSIONS={"3.4.0"}
    source $SDPSOFT_PATH/env.csh --source $ARPACK_NG_VERSION "$ARPACK_NG_VERSIONS" arpack-ng $SILENT_OUTPUT
  endif

  if ( "$?ASTYLE_VERSION" ) then
    set ASTYLE_VERSIONS={"2.05.1"}
    source $SDPSOFT_PATH/env.csh --source $ASTYLE_VERSION "$ASTYLE_VERSIONS" astyle $SILENT_OUTPUT
  endif

  if ( "$?AUTOCONF_VERSION" ) then
    set AUTOCONF_VERSIONS={"2.69"}
    source $SDPSOFT_PATH/env.csh --source $AUTOCONF_VERSION "$AUTOCONF_VERSIONS" autoconf $SILENT_OUTPUT
  endif

  if ( "$?AUTOMAKE_VERSION" ) then
    set AUTOMAKE_VERSIONS={"1.15"}
    source $SDPSOFT_PATH/env.csh --source $AUTOMAKE_VERSION "$AUTOMAKE_VERSIONS" automake $SILENT_OUTPUT
  endif

  if ( "$?BINUTILS_VERSION" ) then
    set BINUTILS_VERSIONS={"2.28"}
    source $SDPSOFT_PATH/env.csh --source $BINUTILS_VERSION "$BINUTILS_VERSIONS" binutils $SILENT_OUTPUT
  endif

  if ( "$?BOOST_VERSION" ) then
    set BOOST_VERSIONS={"1.44.0","1.45","1.58","1.66.0"}
    source $SDPSOFT_PATH/env.csh --source $BOOST_VERSION "$BOOST_VERSIONS" boost $SILENT_OUTPUT
  endif

  if ( "$?CHECK_VERSION" ) then
    set CHECK_VERSIONS={"0.9.5"}
    source $SDPSOFT_PATH/env.csh --source $CHECK_VERSION "$CHECK_VERSIONS" check $SILENT_OUTPUT
  endif

  if ( "$?CLOOG_VERSION" ) then
    set CLOOG_VERSIONS={"0.16.2"}
    source $SDPSOFT_PATH/env.csh --source $CLOOG_VERSION "$CLOOG_VERSIONS" cloog $SILENT_OUTPUT
  endif

  if ( "$?CMAKE_VERSION" ) then
    set CMAKE_VERSIONS={"3.10.2", "3.16.0"}
    source $SDPSOFT_PATH/env.csh --source $CMAKE_VERSION "$CMAKE_VERSIONS" cmake $SILENT_OUTPUT
  endif

  if ( "$?COIN3D_VERSION" ) then
    set COIN3D_VERSIONS={"3.1.3"}
    source $SDPSOFT_PATH/env.csh --source $COIND3D_VERSION "$COIND3D_VERSIONS" coin3d $SILENT_OUTPUT
  endif

  if ( "$?CPPUNIT_VERSION" ) then
    set CPPUNIT_VERSIONS={"1.12.0"}
    source $SDPSOFT_PATH/env.csh --source $CPPUNIT_VERSION "$CPPUNIT_VERSIONS" cppunit $SILENT_OUTPUT
  endif

  if ( "$?CURL_VERSION" ) then
    set CURL_VERSIONS={"7.21.1","7.56.0"}
    source $SDPSOFT_PATH/env.csh --source $CURL_VERSION "$CURL_VERSIONS" curl $SILENT_OUTPUT
  endif

  if ( "$?DELPHI_VERSION" ) then
    set DELPHI_VERSIONS={"41_su40"}
    source $SDPSOFT_PATH/env.csh --source $DELPHI_VERSION "$DELPHI_VERSIONS" delphi $SILENT_OUTPUT
  endif

  if ( "$?DERE_VERSION" ) then
    set DERE_VERSIONS={"1.0"}
    source $SDPSOFT_PATH/env.csh --source $DERE_VERSION "$DERE_VERSIONS" dere $SILENT_OUTPUT
  endif

  if ( "$?DUNE_VERSION" ) then
    set DUNE_VERSIONS={"2.5.1"}
    source $SDPSOFT_PATH/env.csh --source $DUNE_VERSION "$DUNE_VERSIONS" dune $SILENT_OUTPUT
  endif

  if ( "$?EXPAT_VERSION" ) then
    set EXPAT_VERSIONS={"2.1.0"}
    source $SDPSOFT_PATH/env.csh --source $EXPAT_VERSION "$EXPAT_VERSIONS" expat $SILENT_OUTPUT
  endif

  if ( "$?FFTW_VERSION" ) then
    set FFTW_VERSIONS={"2.1.5","3.2.1","3.3.3","3.3.4"}
    source $SDPSOFT_PATH/env.csh --source $FFTW_VERSION "$FFTW_VERSIONS" fftw $SILENT_OUTPUT
  endif

  if ( "$?FREETYPE_VERSION" ) then
    set FREETYPE_VERSIONS={"2.4.12"}
    source $SDPSOFT_PATH/env.csh --source $FREETYPE_VERSION "$FREETYPE_VERSIONS" freetype $SILENT_OUTPUT
  endif

  if ( "$?GCC_VERSION" ) then
    set GCC_VERSIONS={"4.2.4","4.6.1","4.8.2","4.9.4","7.2.0","7.3.0"}
    source $SDPSOFT_PATH/env.csh --source $GCC_VERSION "$GCC_VERSIONS" gcc $SILENT_OUTPUT
  endif

  if ( "$?GDB_VERSION" ) then
    set GDB_VERSIONS={"8.0"}
    source $SDPSOFT_PATH/env.csh --source $GDB_VERSION "$GDB_VERSIONS" gdb $SILENT_OUTPUT
  endif

  if ( "$?GIT_VERSION" ) then
    set GIT_VERSIONS={"1.8.2","1.8.3","2.4.0","2.7.3","2.8.0","2.12.2","2.16.1"}
    source $SDPSOFT_PATH/env.csh --source $GIT_VERSION "$GIT_VERSIONS" git $SILENT_OUTPUT
  endif

  if ( "$?GIT_EXTRAS_VERSION" ) then
    set GIT_EXTRAS_VERSIONS={"3.0.0"}
    source $SDPSOFT_PATH/env.csh --source $GIT_EXTRAS_VERSION "$GIT_EXTRAS_VERSIONS" git-extras $SILENT_OUTPUT
  endif

  if ( "$?GIT_LFS_VERSION" ) then
    set GIT_LFS_VERSIONS={"2.3.0"}
    source $SDPSOFT_PATH/env.csh --source $GIT_LFS_VERSION "$GIT_LFS_VERSIONS" git $SILENT_OUTPUT
  endif

  if ( "$?GLIB_VERSION" ) then
    set GLIB_VERSIONS={"2.54.0"}
    source $SDPSOFT_PATH/env.csh --source $GLIB_VERSION "$GLIB_VERSIONS" glib $SILENT_OUTPUT
  endif

  if ( "$?GLIBC_VERSION" ) then
    set GLIBC_VERSIONS={"2.17","2.23"}
    source $SDPSOFT_PATH/env.csh --source $GLIBC_VERSION "$GLIBC_VERSIONS" glibc $SILENT_OUTPUT
  endif

  if ( "$?GMP_VERSION" ) then
    set GMP_VERSIONS={"5.0.2","5.0.5","5.1.3","6.1.2"}
    source $SDPSOFT_PATH/env.csh --source $GMP_VERSION "$GMP_VERSIONS" gmp $SILENT_OUTPUT
  endif

  if ( "$?GNUPLOT_VERSION" ) then
    set GNUPLOT_VERSIONS={"4.6.5"}
    source $SDPSOFT_PATH/env.csh --source $GNUPLOT_VERSION "$GNUPLOT_VERSIONS" gnuplot $SILENT_OUTPUT
  endif

  if ( "$?GO_VERSION" ) then
    set GO_VERSIONS={"1.2.1","1.4.2","1.6","1.7.3"}
    source $SDPSOFT_PATH/env.csh --source $GO_VERSION "$GO_VERSIONS" go $SILENT_OUTPUT
    if ( "$?" == "0" ) then
      if ( -d "${SDPSOFT_PATH}/go_${GO_VERSION}" ) then
        setenv GOROOT "${SDPSOFT_PATH}/go_$GO_VERSION"
      else if ( -d "${SDPSOFT_PATH}/go-${GO_VERSION}" ) then
        setenv GOROOT "${SDPSOFT_PATH}/go-$GO_VERSION"
      else if ( -d "${SDPSOFT_PATH}/go${GO_VERSION}" ) then
        setenv GOROOT "${SDPSOFT_PATH}/go$GO_VERSION"
      endif
    endif
  endif

  if ( "$?GRACE_VERSION" ) then
    set GRACE_VERSIONS={"5.99.0"}
    source $SDPSOFT_PATH/env.csh --source $GRACE_VERSION "$GRACE_VERSIONS" grace $SILENT_OUTPUT
  endif

  if ( "$?GRT_VERSION" ) then
    set GRT_VERSIONS={"1.4.0","1.4.2","1.5.0","1.5.2"}
    source $SDPSOFT_PATH/env.csh --source $GRT_VERSION "$GRT_VERSIONS" GRT $SILENT_OUTPUT
  endif

  if ( "$?GSL_VERSION" ) then
    set GSL_VERSIONS={"1.9"}
    source $SDPSOFT_PATH/env.csh --source $GSL_VERSION "$GSL_VERSIONS" gsl $SILENT_OUTPUT
  endif

  if ( "$?HDF5_VERSION" ) then
    set HDF5_VERSIONS={"1.8.8"}
    source $SDPSOFT_PATH/env.csh --source $HDF5_VERSION "$HDF5_VERSIONS" hdf5 $SILENT_OUTPUT
  endif

  if ( "$?ICU_VERSION" ) then
    set ICU_VERSIONS={"4.2.1"}
    source $SDPSOFT_PATH/env.csh --source $ICU_VERSION "$ICU_VERSIONS" icu $SILENT_OUTPUT
  endif

  if ( "$?IMAGEMAGICK_VERSION" ) then
    set IMAGEMAGICK_VERSIONS={"6.6.1-5"}
    source $SDPSOFT_PATH/env.csh --source $IMAGEMAGICK_VERSION "$IMAGEMAGICK_VERSIONS" ImageMagick $SILENT_OUTPUT
  endif

  if ( "$?JDK_VERSION" ) then
    set JDK_VERSIONS={"1.6.0_16","1.6.0_27","1.6.0_45","1.7.0_07","1.7.0_11","1.7.0_25","1.7.0_45","1.8.0_11","1.8.0_25","1.8.0_121","1.8.0_162"}
    source $SDPSOFT_PATH/env.csh --source $JDK_VERSION "$JDK_VERSIONS" jdk $SILENT_OUTPUT
  endif

  if ( "$?JQ_VERSION" ) then
    set JQ_VERSIONS={"1.5"}
    source $SDPSOFT_PATH/env.csh --source $JQ_VERSION "$JQ_VERSIONS" jq $SILENT_OUTPUT
  endif

  if ( "$?JSEISIO_VERSION" ) then
    set JSEISIO_VERSIONS={"v1.0","v1.1"}
    source $SDPSOFT_PATH/env.csh --source $JSEISIO_VERSION "$JSEISIO_VERSIONS" jseisio $SILENT_OUTPUT
  endif

  if ( "$?JULIA_VERSION" ) then
    set JULIA_VERSIONS={"0.4.6"}
    source $SDPSOFT_PATH/env.csh --source $JULIA_VERSION "$JULIA_VERSIONS" julia $SILENT_OUTPUT
  endif

  if ( "$?KDIFF3_VERSION" ) then
    set KDIFF3_VERSIONS={"0.9.96"}
    source $SDPSOFT_PATH/env.csh --source $KDIFF3_VERSION "$KDIFF3_VERSIONS" kdiff3 $SILENT_OUTPUT
  endif

  if ( "$?KERNELTOMO_VERSION" ) then
    set KERNELTOMO_VERSIONS={"1.0"}
    source $SDPSOFT_PATH/env.csh --source $KERNELTOMO_VERSION "$KERNELTOMO_VERSIONS" KernelTomo $SILENT_OUTPUT
  endif

  if ( "$?LAPACK_VERSION" ) then
    set LAPACK_VERSIONS={"3.7.0"}
    source $SDPSOFT_PATH/env.csh --source $LAPACK_VERSION "$LAPACK_VERSIONS" lapack $SILENT_OUTPUT
  endif

  if ( "$?LIBECL_VERSION" ) then
    set LIBECL_VERSIONS={"2.3.a2", "2.3.a5"}
    source $SDPSOFT_PATH/env.csh --source $LIBECL_VERSION "$LIBECL_VERSIONS" libecl $SILENT_OUTPUT
  endif

  if ( "$?LIBEVENT_VERSION" ) then
    set LIBEVENT_VERSIONS={"2.0.9-rc"}
    source $SDPSOFT_PATH/env.csh --source $LIBEVENT_VERSION "$LIBEVENT_VERSIONS" libevent $SILENT_OUTPUT
  endif

  if ( "$?LIBFFI_VERSION" ) then
    set LIBFFI_VERSIONS={"3.0.9","3.2.1"}
    source $SDPSOFT_PATH/env.csh --source $LIBFFI_VERSION "$LIBFFI_VERSIONS" libffi $SILENT_OUTPUT
  endif

  if ( "$?LIBNOTIFY_VERSION" ) then
    set LIBNOTIFY_VERSIONS={"0.4.4"}
    source $SDPSOFT_PATH/env.csh --source $LIBNOTIFY_VERSION "$LIBNOTIFY_VERSIONS" libnotify $SILENT_OUTPUT
  endif

  if ( "$?LIBSTATOIL_VERSION" ) then
    set LIBSTATOIL_VERSIONS={"0.1","0.2"}
    source $SDPSOFT_PATH/env.csh --source $LIBSTATOIL_VERSION "$LIBSTATOIL_VERSIONS" libstatoil $SILENT_OUTPUT
  endif

  if ( "$?LIBTASN1_VERSION" ) then
    set LIBTASN1_VERSIONS={"4.12"}
    source $SDPSOFT_PATH/env.csh --source $LIBTASN1_VERSION "$LIBTASN1_VERSIONS" libtasn1 $SILENT_OUTPUT
  endif

  if ( "$?LIBUNISTRING_VERSION" ) then
    set LIBUNISTRING_VERSIONS={"0.9.7"}
    source $SDPSOFT_PATH/env.csh --source $LIBUNISTRING_VERSION "$LIBUNISTRING_VERSIONS" libunistring $SILENT_OUTPUT
  endif

  if ( "$?MADAGASCAR_VERSION" ) then
    # Let Madagascar be source with their own scripts that they provide
    set MADAGASCAR_FOUND=0
    if ( -d "${SDPSOFT_PATH}/madagascar_${MADAGASCAR_VERSION}" ) then
      set MADAGASCAR_FOUND=1
      source "${SDPSOFT_PATH}/madagascar_$MADAGASCAR_VERSION/share/madagascar/etc/env.csh"
    else if ( -d "${SDPSOFT_PATH}/madagascar-${MADAGASCAR_VERSION}" ) then
      set MADAGASCAR_FOUND=1
      source "${SDPSOFT_PATH}/madagascar-$MADAGASCAR_VERSION/share/madagascar/etc/env.csh"
    else if ( -d "${SDPSOFT_PATH}/madagascar${MADAGASCAR_VERSION}" ) then
      set MADAGASCAR_FOUND=1
      source "${SDPSOFT_PATH}/madagascar$MADAGASCAR_VERSION/share/madagascar/etc/env.csh"
    endif
    if ( "$MADAGASCAR_FOUND" == "1" ) then
      if ( "$1" != "--silent" ) then
        printf "${COLOR_GREEN}"
        printf "madagascar $MADAGASCAR_VERSION\n"
        printf "${COLOR_NONE}"
      endif
    else
      printf "${COLOR_YELLOW}"
      printf "madagascar version $MADAGASCAR_VERSION not found. Try searching for versions.\n"
      printf "${COLOR_NONE}"
    endif
  endif

  if ( "$?MERCURIAL_VERSION" ) then
    set MERCURIAL_VERSIONS={"1.6"}
    source $SDPSOFT_PATH/env.csh --source $MERCURIAL_VERSION "$MERCURIAL_VERSIONS" mercurial $SILENT_OUTPUT
  endif

  if ( "$?MPC_VERSION" ) then
    set MPC_VERSIONS={"0.9"}
    source $SDPSOFT_PATH/env.csh --source $MPC_VERSION "$MPC_VERSIONS" mpc $SILENT_OUTPUT
  endif

  if ( "$?MPFR_VERSION" ) then
    set MPFR_VERSIONS={"2.4.2","3.1.0"}
    source $SDPSOFT_PATH/env.csh --source $MPFR_VERSION "$MPFR_VERSIONS" mpfr $SILENT_OUTPUT
  endif

  if ( "$?MPICH_VERSION" ) then
    set MPICH_VERSIONS={"1.2.6_i686","1.2.6_x86_64"}
    source $SDPSOFT_PATH/env.csh --source $MPICH_VERSION "$MPICH_VERSIONS" mpich $SILENT_OUTPUT
  endif

  if ( "$?MPICH2_VERSION" ) then
    set MPICH2_VERSIONS={"1.3.2"}
    source $SDPSOFT_PATH/env.csh --source $MPICH2_VERSION "$MPICH2_VERSIONS" mpich2 $SILENT_OUTPUT
  endif

  if ( "$?NETCDF_VERSION" ) then
    set NETCDF_VERSIONS={"3"}
    source $SDPSOFT_PATH/env.csh --source $NETCDF_VERSION "$NETCDF_VERSIONS" netcdf $SILENT_OUTPUT
  endif

  if ( "$?NETTLE_VERSION" ) then
    set NETTLE_VERSIONS={"3.3"}
    source $SDPSOFT_PATH/env.csh --source $NETTLE_VERSION "$NETTLE_VERSIONS" nettle $SILENT_OUTPUT
  endif

  if ( "$?NODE_VERSION" ) then
    set NODE_VERSIONS={"0.10.12","8.11.2","8.11.3"}
    source $SDPSOFT_PATH/env.csh --source $NODE_VERSION "$NODE_VERSIONS" node $SILENT_OUTPUT
  endif

  if ( "$?OCTAVE_VERSION" ) then
    set OCTAVE_VERSIONS={"4.2.1"}
    source $SDPSOFT_PATH/env.csh --source $OCTAVE_VERSION "$OCTAVE_VERSIONS" octave $SILENT_OUTPUT
  endif

  if ( "$?OPENBLAS_VERSION" ) then
    set OPENBLAS_VERSIONS={"0.2.14", "0.3.6"}
    source $SDPSOFT_PATH/env.csh --source $OPENBLAS_VERSION "$OPENBLAS_VERSIONS" openblas $SILENT_OUTPUT
  endif

  if ( "$?OPENMPI_VERSION" ) then
    set OPENMPI_VERSIONS={"1.2.5","1.2.6","1.2.8","1.4.2","1.6.3","1.6.5","1.8.4"}
    source $SDPSOFT_PATH/env.csh --source $OPENMPI_VERSION "$OPENMPI_VERSIONS" openmpi $SILENT_OUTPUT
    if ( "$?" == "0" ) then
      if ( -d "${SDPSOFT_PATH}/openmpi_${OPENMPI_VERSION}" ) then
        setenv MPI "${SDPSOFT_PATH}/openmpi_$OPENMPI_VERSION"
      else if ( -d "${SDPSOFT_PATH}/openmpi-${OPENMPI_VERSION}" ) then
        setenv MPI "${SDPSOFT_PATH}/openmpi-$OPENMPI_VERSION"
      else if ( -d "${SDPSOFT_PATH}/openmpi${OPENMPI_VERSION}" ) then
        setenv MPI "${SDPSOFT_PATH}/openmpi$OPENMPI_VERSION"
      endif
      if ( "$?FPATH" ) then
        setenv FPATH "$MPI/include:$FPATH"
      else
        setenv FPATH "$MPI/include"
      endif
      setenv OPAL_PREFIX "$MPI"
    endif
  endif

  if ( "$?OPENSSL_VERSION" ) then
    set OPENSSL_VERSIONS={"1.0.2l","1.1.0f", "1.1.1d"}
    source $SDPSOFT_PATH/env.csh --source $OPENSSL_VERSION "$OPENSSL_VERSIONS" openssl $SILENT_OUTPUT
  endif

  if ( "$?OPTARADON_VERSION" ) then
    set OPTARADON_VERSIONS={"r1"}
    source $SDPSOFT_PATH/env.csh --source $OPTARADON_VERSION "$OPTARADON_VERSIONS" OptaRadon $SILENT_OUTPUT
  endif

  if ( "$?OSG_VERSION" ) then
    set OSG_VERSIONS={"2.8.2"}
    source $SDPSOFT_PATH/env.csh --source $OSG_VERSION "$OSG_VERSIONS" osg $SILENT_OUTPUT
  endif

  if ( "$?P11_KIT_VERSION" ) then
    set P11_KIT_VERSIONS={"0.23.2"}
    source $SDPSOFT_PATH/env.csh --source $P11_KIT_VERSION "$P11_KIT_VERSIONS" p11-kit $SILENT_OUTPUT
  endif

  if ( "$?PCRE_VERSION" ) then
    set PCRE_VERSIONS={"8.40"}
    source $SDPSOFT_PATH/env.csh --source $PCRE_VERSION "$PCRE_VERSIONS" pcre $SILENT_OUTPUT
  endif

  if ( "$?PHANTOMJS_VERSION" ) then
    set PHANTOMJS_VERSIONS={"1.6.2-linux-x86_64-dynamic"}
    source $SDPSOFT_PATH/env.csh --source $PHANTOMJS_VERSION "$PHANTOMJS_VERSIONS" phantomjs $SILENT_OUTPUT
  endif

  if ( "$?PHP_VERSION" ) then
    set PHP_VERSIONS={"5.3.8"}
    source $SDPSOFT_PATH/env.csh --source $PHP_VERSION "$PHP_VERSIONS" php $SILENT_OUTPUT
  endif

  if ( "$?PPL_VERSION" ) then
    set PPL_VERSIONS={"0.11.2"}
    source $SDPSOFT_PATH/env.csh --source $PPL_VERSION "$PPL_VERSIONS" ppl $SILENT_OUTPUT
  endif

  if ( "$?PUMA_VERSION" ) then
    set PUMA_VERSIONS={"v1.0","v1.1","v1.2"}
    source $SDPSOFT_PATH/env.csh --source $PUMA_VERSION "$PUMA_VERSIONS" puma $SILENT_OUTPUT
  endif

  if ( "$?PYTHON_VERSION" ) then
    set PYTHON_VERSIONS={"2.4","2.6","2.6.7","2.7.3","2.7.6","2.7.11","2.7.13","2.7.14","2.7.15","3.3.2","3.4.2","3.6.1","3.6.2","3.6.4","3.7.1"}
    source $SDPSOFT_PATH/env.csh --source $PYTHON_VERSION "$PYTHON_VERSIONS" python $SILENT_OUTPUT
  endif

  if ( "$?QHULL_VERSION" ) then
    set QHULL_VERSIONS={"7.2.0"}
    source $SDPSOFT_PATH/env.csh --source $QHULL_VERSION "$QHULL_VERSIONS" qhull $SILENT_OUTPUT
  endif

  if ( "$?QRUPDATE_VERSION" ) then
    set QRUPDATE_VERSIONS={"1.1.2"}
    source $SDPSOFT_PATH/env.csh --source $QRUPDATE_VERSION "$QRUPDATE_VERSIONS" qrupdate $SILENT_OUTPUT
  endif

  if ( "$?QT_VERSION" ) then
    set QT_VERSIONS={"3.3.5","4.6","4.6.2","4.7.1","4.8.4","4.8.6","5.4.2","5.9.1","5.9.6","5.11.1"}
    source $SDPSOFT_PATH/env.csh --source $QT_VERSION "$QT_VERSIONS" qt-x11 $SILENT_OUTPUT
      if ( "$?" == "0" ) then
        if ( -d "${SDPSOFT_PATH}/qt-x11_${QT_VERSION}" ) then
          setenv QT_PATH "${SDPSOFT_PATH}/qt-x11_$QT_VERSION"
        else if ( -d "${SDPSOFT_PATH}/qt-x11-${QT_VERSION}" ) then
          setenv QT_PATH "${SDPSOFT_PATH}/qt-x11-$QT_VERSION"
        else if ( -d "${SDPSOFT_PATH}/qt-x11${QT_VERSION}" ) then
          setenv QT_PATH "${SDPSOFT_PATH}/qt-x11$QT_VERSION"
        endif
      endif
  endif

  if ( "$?RUBY_VERSION" ) then
    set RUBY_VERSIONS={"1.8.7","1.9.3","2.0.0"}
    source $SDPSOFT_PATH/env.csh --source $RUBY_VERSION "$RUBY_VERSIONS" ruby $SILENT_OUTPUT
      if ( "$?" == "0" ) then
        if ( -d "${SDPSOFT_PATH}/ruby_${QT_VERSION}" ) then
          setenv GEM_HOME "${SDPSOFT_PATH}/ruby_$$RUBY_VERSION/lib/ruby/gems/$RUBY_VERSION"
        else if ( -d "${SDPSOFT_PATH}/ruby-${QT_VERSION}" ) then
          setenv GEM_HOME "${SDPSOFT_PATH}/ruby-$$RUBY_VERSION/lib/ruby/gems/$RUBY_VERSION"
        else if ( -d "${SDPSOFT_PATH}/ruby${RUBY_VERSION}" ) then
          setenv GEM_HOME "${SDPSOFT_PATH}/ruby$$RUBY_VERSION/lib/ruby/gems/$RUBY_VERSION"
        endif
      endif
  endif

  if ( "$?SCALA_VERSION" ) then
    set SCALA_VERSIONS={"2.8.0","2.9.1","2.10.0"}
    source $SDPSOFT_PATH/env.csh --source $SCALA_VERSION "$SCALA_VERSIONS" scala $SILENT_OUTPUT
  endif

  if ( "$?SCONS_VERSION" ) then
    set SCONS_VERSIONS={"2.1.0"}
    source $SDPSOFT_PATH/env.csh --source $SCONS_VERSION "$SCONS_VERSIONS" scons $SILENT_OUTPUT
  endif

  if ( "$?SCREENSEIS_VERSION" ) then
    set SCREENSEIS_VERSIONS={"v.2.6","v.2.6.1_amd","v.2.6.2_amd","v.2.6.3_amd"}
    source $SDPSOFT_PATH/env.csh --source $SCREENSEIS_VERSION "$SCREENSEIS_VERSIONS" screenseis $SILENT_OUTPUT
  endif

  if ( "$?SCREENSHOT_VERSION" ) then
    set SCREENSHOT_VERSIONS={"v2.0","v2.0_oslo"}
    source $SDPSOFT_PATH/env.csh --source $SCREENSHOT_VERSION "$SCREENSHOT_VERSIONS" ScreenShot $SILENT_OUTPUT
  endif

  if ( "$?SEPLIB_VERSION" ) then
    set SEPLIB_VERSIONS={"6.5.3"}
    source $SDPSOFT_PATH/env.csh --source $SEPLIB_VERSION "$SEPLIB_VERSIONS" seplib $SILENT_OUTPUT
  endif

  if ( "$?SIMVOLEON_VERSION" ) then
    set SIMVOLEON_VERSIONS={"2.0.1"}
    source $SDPSOFT_PATH/env.csh --source $SIMVOLEON_VERSION "$SIMVOLEON_VERSIONS" simvoleon $SILENT_OUTPUT
  endif

  if ( "$?SOQT_VERSION" ) then
    set SOQT_VERSIONS={"1.5.0"}
    source $SDPSOFT_PATH/env.csh --source $SOQT_VERSION "$SOQT_VERSIONS" soqt $SILENT_OUTPUT
  endif

  if ( "$?SUITESPARSE_VERSION" ) then
    set SUITESPARSE_VERSIONS={"4.5.4"}
    source $SDPSOFT_PATH/env.csh --source $SUITESPARSE_VERSION "$SUITESPARSE_VERSIONS" suitesparse $SILENT_OUTPUT
  endif

  if ( "$?SU_VERSION" ) then
    set SU_VERSIONS={"40","42","43_R3","43_R6"}
    source $SDPSOFT_PATH/env.csh --source $SU_VERSION "$SU_VERSIONS" SU $SILENT_OUTPUT
    setenv CWPROOT "$SDPSOFT_PATH/SU_$SU_VERSION/"
  endif

  if ( "$?SVFTOOLS_VERSION" ) then
    set SVFTOOLS_VERSIONS={"r4","r5","r12","r17"}
    source $SDPSOFT_PATH/env.csh --source $SVFTOOLS_VERSION "$SVFTOOLS_VERSIONS" svftools $SILENT_OUTPUT
  endif

  if ( "$?TCL_VERSION" ) then
    set TCL_VERSIONS={"8.4.20","8.6.3"}
    source $SDPSOFT_PATH/env.csh --source $TCL_VERSION "$TCL_VERSIONS" tcl $SILENT_OUTPUT
  endif

  if ( "$?TIGER_VERSION" ) then
    set TIGER_VERSIONS={"v0.7.1","v0.7.2","v0.7.2-1"}
    source $SDPSOFT_PATH/env.csh --source $TIGER_VERSION "$TIGER_VERSIONS" tiger $SILENT_OUTPUT
  endif

  if ( "$?TK_VERSION" ) then
    set TK_VERSIONS={"8.4.20","8.6.3"}
    source $SDPSOFT_PATH/env.csh --source $TK_VERSION "$TK_VERSIONS" tk $SILENT_OUTPUT
  endif

  if ( "$?TMUX_VERSION" ) then
    set TMUX_VERSIONS={"2.6"}
    source $SDPSOFT_PATH/env.csh --source $TMUX_VERSION "$TMUX_VERSIONS" tmux $SILENT_OUTPUT
  endif

  if ( "$?TORQUE_VERSION" ) then
    set TORQUE_VERSIONS={"6.1.0"}
    source $SDPSOFT_PATH/env.csh --source $TORQUE_VERSION "$TORQUE_VERSIONS" torque $SILENT_OUTPUT
  endif

  if ( "$?WX_VERSION" ) then
    set WX_VERSIONS={"2.9.1.1"}
    source $SDPSOFT_PATH/env.csh --source $WX_VERSION "$WX_VERSIONS" wx $SILENT_OUTPUT
  endif

  if ( "$?ZEROMQ_VERSION" ) then
    set ZEROMQ_VERSIONS={"4.2.1"}
    source $SDPSOFT_PATH/env.csh --source $ZEROMQ_VERSION "$ZEROMQ_VERSIONS" zeromq $SILENT_OUTPUT
  endif

  if ( "$?GRPC_VERSION" ) then
    set GRPC_VERSIONS={"1.20.1"}
    source $SDPSOFT_PATH/env.csh --source $GRPC_VERSION "$GRPC_VERSIONS" grpc $SILENT_OUTPUT
  endif

endif
