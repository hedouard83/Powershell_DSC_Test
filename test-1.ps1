Configuration ServerConfig
{
  Node Anybody
  {
    # Leaves a timestamp indicating the last time this script was run on the node (this resource is intentionally not idempotent)
    Script LeaveTimestamp
    {
      SetScript = {
        $currentTime = Get-Date
        $currentTimeString = $currentTime.ToUniversalTime().ToString()
        [Environment]::SetEnvironmentVariable("DSCClientRun","Last DSC-Client run (UTC): $currentTimeString","Machine")
        eventcreate /t INFORMATION /ID 1 /L APPLICATION /SO "DSC-Client" /D "Last DSC-Client run (UTC): $currentTimeString"
    }
    TestScript = {
      $false
    }
    GetScript = {
      # Do Nothing
    }
  }

  # Enables remote desktop access to the server
  Registry EnableRDP-Step1
  {
    Ensure = "Present"
    Key = "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Terminal Server"
    ValueName = "fDenyTSConnections"
    ValueData = "0"
    ValueType = "Dword"
    Force = $true
  }

  Registry EnableRDP-Step2
  {
    Ensure = "Present"
    Key = "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
    ValueName = "UserAuthentication"
    ValueData = "1"
    ValueType = "Dword"
    Force = $true
  }

  Script EnableRDP
  {
    SetScript = {
      Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
      eventcreate /t INFORMATION /ID 2 /L APPLICATION /SO "DSC-Client" /D "Enabled Remote Desktop access"
    }
    TestScript = {
      if ((Get-NetFirewallRule -Name "RemoteDesktop-UserMode-In-TCP").Enabled -ne "True") {
        $false
      } else {
        $true
      }
    }
    GetScript = {
      # Do Nothing
    }
  }

  # Disables checking for updates
  Script DisableUpdates
  {
    SetScript = {
      $WUSettings = (New-Object -com "Microsoft.Update.AutoUpdate").Settings
      $WUSettings.NotificationLevel = 1
      $WUSettings.save()
      eventcreate /t INFORMATION /ID 3 /L APPLICATION /SO "DSC-Client" /D "Disabled Checking for Updates"
    }
    TestScript = {
      $WUSettings = (New-Object -com "Microsoft.Update.AutoUpdate").Settings
      if ($WUSettings.NotificationLevel -ne "1") {
        $true
      } else {
        $false
      }
     }
     GetScript = {
       # Do Nothing
     }
   }

   # Verifies Windows Remote Management is Configured or Configures it
   Script EnableWinrm
   {
     SetScript = {
       Set-WSManQuickConfig -Force -SkipNetworkProfileCheck
       eventcreate /t INFORMATION /ID 4 /L APPLICATION /SO "DSC-Client" /D "Enabled Windows Remote Management"
     }
     TestScript = {
       try{
         # Use to remove a listener for testing
         # Remove-WSManInstance winrm/config/Listener -selectorset @{Address="*";Transport="http"}
         Get-WsmanInstance winrm/config/listener -selectorset @{Address="*";Transport="http"}
         return $true
       } catch {
         #$wsmanOutput = "WinRM doesn't seem to be configured or enabled."
         return $false
       }
     }
     GetScript = {
       # Do Nothing
     }
   }

   # Installs the Applicaiton-Server Role
   Script InstallAppServer-LogEvent
     {
       SetScript = {
         eventcreate /t INFORMATION /ID 6 /L APPLICATION /SO "DSC-Client" /D "Installed Role: Applicaiton-Server"
       }
       TestScript = {
         if ((Get-WindowsFeature -Name Application-Server).Installed) {
           $true
         } else {
           $false
         }
       }
       GetScript = {
         # Do Nothing
       }
     }

     WindowsFeature InstallAppServer-Step1
     {
       Name = "Application-Server"
       Ensure = "Present"
       IncludeAllSubFeature = $true
     }

     WindowsFeature InstallAppServer-Step2
     {
       Name = "AS-Web-Support"
       Ensure = "Present"
       IncludeAllSubFeature = $true
       DependsOn = "[WindowsFeature]InstallAppServer-Step1"
     }

     # Disables Shutdown tracking (asking for a reason for shutting down the server)
     Script DisableShutdownTracking-LogEvent
     {
       SetScript = {
         eventcreate /t INFORMATION /ID 7 /L APPLICATION /SO "DSC-Client" /D "Disabled Shutdown Tracking"
      }
      TestScript = {
        if ((Get-ItemProperty -Path 'HKLM:\\SOFTWARE\Policies\Microsoft\Windows NT\Reliability').ShutdownReasonOn -ne "0") {
          $false
        } else {
          $true
        }
      }
      GetScript = {
        # Do Nothing
      }
    }

    Registry DisableShutdownTracking
    {
      Ensure = "Present"
      Key = "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\Reliability"
      ValueName = "ShutdownReasonOn"
      ValueData = "0"
      ValueType = "Dword"
      Force = $true
    }
  }
}

# The MOF filename must be a GUID. It can be any unique GUID and can be generated by the following PowerShell command ([guid]::NewGuid()).
$guid = "45b51dc8-132c-4052-8e3b-479c73d4c9cc"

# Create the MOF file from the above PowerShell DSC script
ServerConfig

# Used to copy the newly generated MOF file in the Pull Server's publishing location
$mofFile = "c:\dscscripts\ServerConfig\Anybody.mof"
$mofPath = "C:\Program Files\WindowsPowerShell\DscService\Configuration"
$DSCMofFile = $mofPath + "\" + $guid + ".mof"

Copy-Item $mofFile -Destination $DSCMofFile
# Generate a CheckSum sister file for the MOF file
New-DSCCheckSum $DSCMofFile -Force
