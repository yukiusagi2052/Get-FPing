
<#
  Title    : Get-FPing
  Version  : 0.1
  Updated  : 2015/5/13

  Tested   : Powershell 4.0
#>

<#
  Windows Pingコマンド オプション
    -n 要求数       送信するエコー要求の数です
    -f              パケット内の Don't Fragment フラグを設定します (IPv4 のみ)
    -w タイムアウト 応答を待つタイムアウトの時間 (ミリ秒) です
    -l サイズ       送信バッファーのサイズです
#>

# 
# パラメーター
#

# TTL初期値
[Int]$OriginTTL = 128

# 引数
function Get-FPing {
  [OutputType('System.Management.Automation.PSObject')]
  [CmdletBinding()]
  Param(
    [Parameter(Mandatory=$True,Position=1, HelpMessage='What computer name would you like to target?')]
    [String] $Target,

    [Parameter(HelpMessage='number of pings to send to each host')]
    [Alias('n')]
    [Int] $number = 20,

    [Parameter(HelpMessage='Set Dont Flagment')]
    [Alias('f')]
    [Switch] $DontFlagment,

    [Parameter(HelpMessage='timeout in ms to wait for each reply')]
    [Alias('w')]
    [Int] $timeout = 1000,

    [Parameter(HelpMessage='amount of data in bytes up to 65500')]
    [Alias('l')]
    [Int] $size = 0,

    [Parameter(HelpMessage='interval time in ms for next icmp request')]
    [Int] $interval = 10,

    [Parameter(HelpMessage='return all Round Trip Times')]
    [switch]$RawRTTs,

    [Parameter(HelpMessage='return raw data')]
    [switch]$RawData
  )

  #
  # グローバル変数
  #

  # Ping 結果リスト
  $Global:MyPingResult = @()



  #
  # メイン処理
  #

  # address
  # Type: System.String
  # A String that identifies the computer that is the destination for the ICMP echo message. 
  # The value specified for this parameter can be a host name or a string representation of an IP address.
  [String] $address = $Target
  
  <# ToDo $Target のチェック
    ・FQDNの場合は、IPアドレスが引けるかチェック
　　・IPアドレスの場合は、正規表現でチェック
  #>

  # timeout
  # Type: System.Int32
  # An Int32 value that specifies the maximum number of milliseconds (after sending 
  # the echo message) to wait for the ICMP echo reply message.

  # buffer
  # Type: System.Byte()
  # A Byte array that contains data to be sent with the ICMP echo message and returned 
  # in the ICMP echo reply message. The array cannot contain more than 65,500 bytes.
  If ( $size -lt 65500) {
    [byte[]]$buffer = New-Object byte[] -ArgumentList $size
  } Else {
    Write-Error "specified size is too large."
    return
  }

  # PingOptions
  # Type: System.Net.NetworkInformation.PingOptions
  # A PingOptions object used to control fragmentation and Time-to-Live values for the ICMP echo message packet.
  [System.Net.NetworkInformation.PingOptions] $PingOptions = New-Object System.Net.NetworkInformation.PingOptions
  If ($DontFlagment) {
    $PingOptions.DontFragment = $true
  } Else {
    $PingOptions.DontFragment = $false
  }

  $PingOptions.ttl = $OriginTTL

  # userToken
  # Type: System.Object
  # An object that is passed to the method invoked when the asynchronous operation completes.
  $userToken = $Targe



  For ([Int]$i=0; $i -lt $number; $i++) {

    [System.Net.NetworkInformation.Ping]$Ping = New-Object System.Net.NetworkInformation.Ping

    #
    # Ping非同期実行すると、Ping完了時にPingCompleteed イベント発生する
    # 非同期実行前に、Ping実行完了時の処理内容を記述し、登録する
    #
    Register-ObjectEvent -Action {

      #結果をグローバル変数へ、オブジェクトとして追加
      $Global:MyPingResult += New-Object PSObject -Property @{
        time = $Event.TimeGenerated
        status = $Event.SourceEventArgs.Reply.Status
        address = $Event.SourceEventArgs.Reply.Address
        RoundtripTime = $Event.SourceEventArgs.Reply.RoundtripTime
        ttl = $Event.SourceEventArgs.Reply.Options.ttl
      }

      #Eventを停止し、登録削除
      Unregister-Event -SourceIdentifier $EventSubscriber.SourceIdentifier #stop job
      #Remove-Job -Name $EventSubscriber.SourceIdentifier #remove job

    } -EventName PingCompleted -InputObject $Ping > $null

    #
    # 非同期Ping 実行
    #
    $Ping.SendAsync($address, $timeout, $buffer, $PingOptions, $userToken)

    Start-Sleep -Milliseconds $interval
  }

  #
  # 複数実行中 の 非同期Ping 進捗確認
  #
  [bool]$JobRunning = $false #実行中Job の 有無確認フラグ

  Do{
    Start-Sleep -Milliseconds 500

    $JobRunning = $false #reset
    Get-Job | ForEach-Object {
      If ($_.State -ne "Stopped") { $JobRunning = $true }
    }

  } While ( $JobRunning )

  Get-Job | ForEach-Object{ Remove-Job -Name $_.Name }

  #
  # 集計処理
  #
  [Int]$Total = 0 #合計
  [Int]$Success = 0 #成功
  [Int]$TimedOut = 0 #失敗
  [Int]$Other = 0 #その他結果
  [Double]$SuccessRate = 0 #成功率
  [Double]$LossRate = 0 #失敗率
  [Int[]]$RTTs = @() #全RTTデータ

  $Total = $Global:MyPingResult.length

  ForEach ($r in $Global:MyPingResult) {
    # 件数カウント
    Switch ($r.status){
      "Success" { $Success++ }
      #The ICMP echo request succeeded; an ICMP echo reply was received. 
      #When you get this status code, the other PingReply properties contain valid data.
      "TimedOut" { $TimedOut++ }
      #The ICMP echo Reply was not received within the allotted time. The default time 
      #allowed for replies is 5 seconds. You can change this value using the Send or SendAsync
      # methods that take a timeout parameter.
      "DestinationNetworkUnreachable" { $Other++ }
      #The ICMP echo request failed because the network 
      #that contains the destination computer is not reachable.
      "DestinationHostUnreachable" { $Other++ }
      #The ICMP echo request failed because the destination computer is not reachable.
      "DestinationProtocolUnreachable" { $Other++ }
      #The ICMP echo request failed because the destination computer that is specified 
      #in an ICMP echo message is not reachable, because it does not support the packet's protocol.
      "DestinationPortUnreachable" { $Other++ }
      #The ICMP echo request failed because the port on the destination computer is not available.
      "DestinationProhibited" { $Other++ }
      #The ICMP echo request failed because contact with the destination computer is administratively prohibited.
      "NoResources" { $Other++ }
      #The ICMP echo request failed because of insufficient network resources.
      "BadOption" { $Other++ }
      #The ICMP echo request failed because it contains an invalid option.
      "HardwareError" { $Other++ }
      #The ICMP echo request failed because of a hardware error.
      "PacketTooBig" { $Other++ }
      #The ICMP echo request failed because the packet containing the request is larger than
      #the maximum transmission unit (MTU) of a node (router or gateway) located 
      #between the source and destination. The MTU defines the maximum size of a transmittable packet.
      "BadRoute" { $Other++ }
      #The ICMP echo request failed because there is no valid route between the source and destination computers.
      "TtlExpired" { $Other++ }
      #The ICMP echo request failed because its Time to Live (TTL) value reached zero, 
      #causing the forwarding node (router or gateway) to discard the packet.
      "TtlReassemblyTimeExceeded" { $Other++ }
      #The ICMP echo request failed because the packet was divided into fragments for 
      #transmission and all of the fragments were not received within the time allotted 
      #for reassembly. RFC 2460 (available at www.ietf.org) specifies 60 seconds 
      #as the time limit within which all packet fragments must be received.
      "ParameterProblem" { $Other++ }
      #The ICMP echo request failed because a node (router or gateway) encountered 
      #problems while processing the packet header. This is the status if, 
      #for example, the header contains invalid field data or an unrecognized option.
      "SourceQuench" { $Other++ }
      #The ICMP echo request failed because the packet was discarded. This occurs 
      #when the source computer's output queue has insufficient storage space, 
      #or when packets arrive at the destination too quickly to be processed.
      "BadDestination" { $Other++ }
      #The ICMP echo request failed because the destination IP address cannot 
      #receive ICMP echo requests or should never appear in the destination address field 
      #of any IP datagram. For example, calling Send and specifying IP address "000.0.0.0" returns this status.
      "DestinationUnreachable" { $Other++ }
      #The ICMP echo request failed because the destination computer that is specified 
      #in an ICMP echo message is not reachable; the exact cause of problem is unknown.
      "TimeExceeded" { $Other++ }
      #The ICMP echo request failed because its Time to Live (TTL) value reached zero, 
      #causing the forwarding node (router or gateway) to discard the packet.
      "BadHeader" { $Other++ }
      #The ICMP echo request failed because the header is invalid.
      "UnrecognizedNextHeader" { $Other++ }
      #The ICMP echo request failed because the Next Header field does not contain 
      #a recognized value. The Next Header field indicates the extension header type 
      #(if present) or the protocol above the IP layer, for example, TCP or UDP.
      "IcmpError" { $Other++ }
      #The ICMP echo request failed because of an ICMP protocol error.
      "DestinationScopeMismatch" { $Other++ }
      #The ICMP echo request failed because the source address and destination 
      #address that are specified in an ICMP echo message are not in the same scope. 
      #This is typically caused by a router forwarding a packet using an interface 
      #that is outside the scope of the source address. Address scopes (link-local, 
      #site-local, and global scope) determine where on the network an address is valid.
      "Unknown" { $Other++ }
      #The ICMP echo request failed for an unknown reason.
      default{ $Other++ }
    }

    If ($r.status -eq "Success") {
      # RTT取得
      $RTTs += $r.RoundtripTime
    }

  }

  # Ping成功率、失敗率 の算出
  $SuccessRate = [Double]$Success / [Double]$Total * 100
  $LossRate = [Double]($TimedOut + $Other) / [Double]$Total * 100

  # 最大RTT、最少RTT、平均RTT の算出
  $MeasuredRTTs = $RTTs | Measure-Object -Average -Maximum -Minimum

  # RTT中央値 の算出
  If ($RTTs -ne $Null){
    $SortedRTTs = $RTTs |sort
    if ($SortedRTTs.count%2) {
      #odd
      $RttMedian = $SortedRTTs[[math]::Floor($SortedRTTs.count/2)]
    }
    else {
      #even
      $RttMedian = ($SortedRTTs[$SortedRTTs.Count/2],$SortedRTTs[$SortedRTTs.count/2-1] |measure -Average).average
    }
  } Else {
      $RttMedian = $Null
  }

  # RTT標準偏差 の 算出
  If ($RTTs -ne $Null){
    [Double]$popdev = 0
    $RTTs | ForEach-Object{
      $popdev +=  [math]::pow(($_ - $MeasuredRTTs.Average), 2)
    }
    [Double]$RttSd = [math]::sqrt($popdev / ($MeasuredRTTs.Count))
  } Else {
    [Double]$RttSd = $Null
  }

  #戻り値
  $object = New-Object PSObject -Property @{
    Address = $address
    Count = $Total
    SuccessRate = $SuccessRate
    LossRate = $LossRate
    RttAverage = $MeasuredRTTs.Average
    RttMax = $MeasuredRTTs.Maximum
    RttMin = $MeasuredRTTs.Minimum
    RttMedian = $RttMedian
    RttSd = $RttSd
  }
  If($RawRTTs){ $object | Add-Member –MemberType NoteProperty –Name RTTs –Value $RTTs}
  If($RawData){ $object | Add-Member –MemberType NoteProperty –Name RawData –Value $Global:MyPingResult}
  Write-Output $object

  #終了処理
  $Global:MyPingResult = $null

} #Function Get-FPing ここまで
