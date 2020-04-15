# ----------------------------------------------------------------------------------
#
# Copyright Microsoft Corporation
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------------

# Requirements:
# Powershell
# Az module: Install-Module Az

<#
.SYNOPSIS
Initiate JIT network access policy request
#>
function Connect-AzVM()
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ParameterSetName="Default", Position=0)]
        [string] $VMName,
        [Parameter(Mandatory=$false, ParameterSetName="Default", Position=1)]
        [string] $RGType

    )


    Set-AzContext -Subscription "S066-SDP-Tools-Classic"

    $RGType = "internal"
    $RGName = "sdp-$RGType-vms"

	[Microsoft.Azure.Commands.Security.Models.JitNetworkAccessPolicies.PSSecurityJitNetworkAccessPolicyInitiateVirtualMachine]$vm = New-Object -TypeName Microsoft.Azure.Commands.Security.Models.JitNetworkAccessPolicies.PSSecurityJitNetworkAccessPolicyInitiateVirtualMachine
	$vm.Id = "/subscriptions/47dd9472-aaea-401b-add5-55fccfe63434/resourceGroups/sdp-external-vms/providers/Microsoft.Compute/virtualMachines/$vmName"
	[Microsoft.Azure.Commands.Security.Models.JitNetworkAccessPolicies.PSSecurityJitNetworkAccessPolicyInitiatePort]$port = New-Object -TypeName Microsoft.Azure.Commands.Security.Models.JitNetworkAccessPolicies.PSSecurityJitNetworkAccessPolicyInitiatePort
	$port.AllowedSourceAddressPrefix = "127.0.0.1"
	$port.EndTimeUtc = [DateTime]::UtcNow.AddHours(2)
	$port.Number = 22
	$vm.Ports = (,$port)

    Start-AzJitNetworkAccessPolicy -ResourceGroupName $RGName -Location "norwayeast" -Name "OP-VMs-JIT-Policy" -VirtualMachine (,$vm)

    ssh root@"$vmName".sdp.equinor.com
}


