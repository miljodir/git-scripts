#!/bin/bash
# Generates terraform "import" blocks based on a local terraform state file.
# Usage: ./import-existing.sh <group_name>

generate_import_block() {
    local group_name="$1"
    jq -r --arg name "$group_name" '
        [.resources[] | select(.type=="azuread_group" and .name==$name)] 
        | .[] 
        | "import {\n  to = \(.module).azuread_group_without_members.\($name)\n  id = \"groups/\(.instances[0].attributes.object_id)\"\n}"
    ' terraform.tfstate >> import-blocks.tf
}

generate_import_block "$1"
