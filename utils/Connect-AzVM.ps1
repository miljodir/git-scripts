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
# Powershell 7.0 or newer
# Az module: Install-Module Az
# Activate PIM role "Omnia contributor" is needed to activate JiT. Per April 2020 this is not available in powershell 7.x, port from 5.x might come

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
        [string] $RGType,
        [Parameter(Mandatory=$false, ParameterSetName="Default", Position=2)]
        [switch] $Fast

    )

    $RGType = "external"
    $RGName = "sdp-$RGType-vms"

    if (!$fast) { # Use -Fast switch to skip JiT and waiting

    Set-AzContext -Subscription "S066-SDP-Tools-Classic"

    Import-Module Az.Resources

    $localIP = Get-NetIPAddress | Select-Object -Property IPAddress | Where-Object -Property IPAddress -Like "10.*"

	[Microsoft.Azure.Commands.Security.Models.JitNetworkAccessPolicies.PSSecurityJitNetworkAccessPolicyInitiateVirtualMachine]$vm = New-Object -TypeName Microsoft.Azure.Commands.Security.Models.JitNetworkAccessPolicies.PSSecurityJitNetworkAccessPolicyInitiateVirtualMachine
	$vm.Id = "/subscriptions/47dd9472-aaea-401b-add5-55fccfe63434/resourceGroups/$RGName/providers/Microsoft.Compute/virtualMachines/$VMName"
	[Microsoft.Azure.Commands.Security.Models.JitNetworkAccessPolicies.PSSecurityJitNetworkAccessPolicyInitiatePort]$port = New-Object -TypeName Microsoft.Azure.Commands.Security.Models.JitNetworkAccessPolicies.PSSecurityJitNetworkAccessPolicyInitiatePort
	$port.AllowedSourceAddressPrefix = $localIP
	$port.EndTimeUtc = [DateTime]::UtcNow.AddHours(2)
	$port.Number = 22
	$vm.Ports = (,$port)

    Start-AzJitNetworkAccessPolicy -ResourceGroupName $RGName -Location "norwayeast" -Name "OP-VMs-JIT-Policy" -VirtualMachine (,$vm)

    if ($?) {
        Write-Host "Successfully sent JiT request, now waiting 30 secs before connecting as the port opening takes some time ..."
    }
    Start-Sleep 30

}
    ssh -i $HOME/.ssh/id_rsa root@"$vmName".sdp.equinor.com
}

# Recommended: Add the above to powershell profile at $PROFILE. Alternatively you can figure out how to run it from a bash/zsh context. "pwsh ./Connect-AzVM -vmname vm31" might work
# Regular Example: Connect-AzVM -rgtype internal -VMName $VMName (rgtype is optional, default external)
# Per 20/04/2020 only vm32 requires JiT. This will likely be subject to change.
