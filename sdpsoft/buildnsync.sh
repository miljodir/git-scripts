#! /usr/bin/bash

PROGRAMNAME=$(basename $0)
cd $(dirname $0)


function usage {
    echo "usage: $PROGRAMNAME DIRECTORY"
    echo -e "Name of the application directory containing the Dockerfile. Example: \"./$PROGRAMNAME python-2.7.14\""
    echo ""
    echo " Prerequisites:" 
    echo " - The user are a member of the 'docker' group"
    echo " - This git repo has the latest Dockerfile you want to compile"
    echo " - The user have ssh access to test01.dev.sdp.statoil.no"
    echo " - The user have ssh access to sdpadm on vmm03"
    echo ""
}

if [ $1 = '-h' ] || [ $1 = '--help' ]; then
    usage
    exit 0
fi

if [[ $1 = *"/"* ]]; then
    echo "Error: Detected '/' in the filename '$1'. This is not allowed to avoid any overwrite of sdpsoft."
    echo "Exiting..."
    exit 1
fi

SOFTWARE=$(echo "$1" | cut --delimiter "-" --fields 1)
VERSION=$(echo "$1" | cut --delimiter "-" --fields 2)

cd $1

docker build --rm -t $SOFTWARE:$VERSION .

docker run -v $PWD/temporary:/temporary $SOFTWARE:$VERSION mv /prog/sdpsoft/$SOFTWARE-$VERSION /temporary/

cd temporary

echo "-------------------------------------------"
echo "| Pushing your software to the test-server |"
echo "-------------------------------------------"
rsync -a $1 test01.dev.sdp.statoil.no:/prog/sdpsoft/
echo "The software is now available on test01.dev.sdp.statoil.no:/prog/sdpsoft"

echo "----------------------------------------------"
echo "| Pushing your software to the staging-server |"
echo "----------------------------------------------"
rsync -a $1 sdpadm@vmm03.prod.sdp.statoil.no:/data/sdpsoft/$1
echo "The software is now available on vmm03.prod.sdp.statoil.no:/data/sdpsoft"
echo "To sync this software to the entire SDPSoft, run './sync.sh -f $1' as sdpadm on vmm03"

cd ..
rm -rf temporary

exit 0
