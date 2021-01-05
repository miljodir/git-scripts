#!/usr/bin/env bash

servers=(
tr-vsdp02.tr.statoil.no
tr-vsdp03.tr.statoil.no
vm01.sdp.equinor.com
vm02.sdp.equinor.com
vm03.sdp.equinor.com
vm31.sdp.equinor.com
vm32.sdp.equinor.com
vm33.sdp.equinor.com
vm35.sdp.equinor.com
vm36.sdp.equinor.com
)

for i in "${servers[@]}"
do
   : 
    echo "./ca.crt $i:/etc/sensu/ssl/"
done