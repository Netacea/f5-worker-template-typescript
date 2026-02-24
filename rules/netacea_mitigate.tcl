when HTTP_REQUEST {
  set http_request_time [clock clicks -milliseconds]
  if {[catch {ILX::init "Netacea" "netacea"} handle]} {
    log local0.error  "Client - [IP::client_addr], ILX failure: could not reach ILX plugin - make sure it is running in the ILX plugin console"
    # Send user graceful error message, then exit event
    set error 1
    return
  }

  set method [HTTP::method]
  set uri [HTTP::uri]
  set useragent [HTTP::header value "User-Agent"]
  set referer [HTTP::header value "referer"]
  # strip route domain from ip
  set clientaddress [regsub {%.*} [IP::client_addr] ""]

  # Collect header names for worker to compute a fingerprint hash
  set headerNames [join [HTTP::header names] ","]

  # Handle Captcha
  if { [HTTP::path] equals "/AtaVerifyCaptcha" && [string tolower $method] eq "post"} {
    # Check if there is a Content-Length header
    if { [HTTP::header exists "Content-Length"] } {
      if { [HTTP::header "Content-Length"] > 64000 }{
        # Content-Length over 64kb so collect 64kb
        set content_length 64000
      } else {
        # Content-Length under 64kb so collect actual length
        set content_length [HTTP::header "Content-Length"]
      }
    } else {
      # Response did not have Content-Length header, so use default of 1Mb
      set content_length 64000
    }
    # Don't collect content if Content-Length header value was 0
    if { $content_length > 0 } {
      HTTP::collect $content_length
    }
    } else { # Check reputation
        # Empty "" body placeholder at index 5 keeps headerNames at index 6,
        # since the worker extracts params by fixed positional index.
        # Body is "" here (non-POST), but [HTTP::payload] for captcha POST in HTTP_REQUEST_DATA.
        if {[catch {ILX::call $handle handleRequest $clientaddress $useragent $method [HTTP::path] [HTTP::header value "cookie"] "" $headerNames} result]} {
          log local0.error  "Client - $clientaddress, ILX failure: could not reach mitigate API: $result"
          # 8 elements to match new reply format (index 7 = empty fingerprint)
          set result {"" 0 [] "" false "" [] ""}
          # Send user graceful error message, then exit event
          return
        }

    # >= 7 instead of == 7 for backwards compat with old 7-element replies
    if {[info exists result] && [llength $result] >= 7}{
      set body  [ lindex $result 0 ]
      set apiCallStatus [ lindex $result 1 ]
      set cookies [ lindex $result 2 ]
      set sessionStatus [ lindex $result 3 ]
      set mitigated [ lindex $result 4 ]
      set mitata [ lindex $result 5 ]
      set injectHeaders [ lindex $result 6]
      # Worker-computed fingerprint at index 7, forwarded to ingest below
      if {[llength $result] >= 8} {
        set headerFingerprint [ lindex $result 7 ]
      } else {
        set headerFingerprint ""
      }
      set ilx_request_time [clock clicks -milliseconds]
      set HTTP::mitata $mitata
      set HTTP::sessionStatus $sessionStatus

      if { $mitigated } then {
        # calculate request time
        set http_response_time [clock clicks -milliseconds]
        set request_time [ expr {$http_response_time - $http_request_time} ]
        # Forward fingerprint at index 11 so ingest logs it as HeaderHash
        ILX::call $handle ingest $clientaddress $useragent 403 $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time $mitata $sessionStatus $headerFingerprint
        HTTP::respond 403 content $body Set-Cookie [join $cookies "; "]
      }
      if { [llength $injectHeaders] == 3} {
        HTTP::header insert "x-netacea-match" [ lindex $injectHeaders 0 ]
        HTTP::header insert "x-netacea-mitigate" [ lindex $injectHeaders 1 ]
        HTTP::header insert "x-netacea-captcha" [ lindex $injectHeaders 2 ]
        HTTP::header insert "x-netacea-event-id" [ lindex $injectHeaders 3 ]
      }
    }
  }
}

when HTTP_REQUEST_DATA {
  if { [HTTP::path] equals "/AtaVerifyCaptcha" && [string tolower $method] eq "post"} {  # Handle Captcha tests
    set method [HTTP::method]
    set uri [HTTP::uri]
    set useragent [HTTP::header value "User-Agent"]
    # strip route domain from ip
    set clientaddress [regsub {%.*} [IP::client_addr] ""]

    # Collected again because HTTP_REQUEST_DATA is a separate event
    set headerNames [join [HTTP::header names] ","]

    # Added headerNames at index 6 (body/payload already at index 5)
    if {[catch {ILX::call $handle handleRequest $clientaddress $useragent $method [HTTP::path] [HTTP::header value "cookie"] [HTTP::payload] $headerNames} result]} {
      log local0.error  "Client - $clientaddress, ILX failure: could not handle captcha test"
      # Send user graceful error message, then exit event
      return
    }
    set body  [ lindex $result 0 ]
    set apiCallStatus [ lindex $result 1 ]
    set cookies [ lindex $result 2 ]
    set sessionStatus [ lindex $result 3 ]
    set mitigated [ lindex $result 4 ]
    set mitata [ lindex $result 5 ]
    set injectHeaders [ lindex $result 6]
    # Extract fingerprint from reply to forward to ingest
    if {[llength $result] >= 8} {
      set headerFingerprint [ lindex $result 7 ]
    } else {
      set headerFingerprint ""
    }
    foreach cookie $cookies {
      HTTP::header insert "Set-Cookie" $cookie
    }

    # calcuate request time
    set http_response_time [clock clicks -milliseconds]
    set request_time [ expr {$http_response_time - $http_request_time} ]
    # Forward fingerprint at index 11 so ingest logs it as HeaderHash
    if {[catch {ILX::call $handle ingest $clientaddress $useragent 403 $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time $mitata $sessionStatus $headerFingerprint} result]} {
      log local0.error  "Client - $clientaddress, ILX failure: could not reach ingest API for passed captcha"
      # Send user graceful error message, then exit event
      return
    }

    HTTP::respond 403 content $body Set-Cookie [lindex $cookies 0] Set-Cookie [lindex $cookies 1]
  }
}

when HTTP_RESPONSE {
  # Put set-cookie header together and get mitata cookie value
  if {[info exists cookies]}{
    foreach cookie $cookies {
      HTTP::header insert "Set-Cookie" $cookie
    }
  }
  set clientaddress [regsub {%.*} [IP::client_addr] ""]

  # calculate request time
  set http_response_time [clock clicks -milliseconds]
  set request_time [ expr {$http_response_time - $http_request_time} ]

  # >= 7 instead of == 7 for backwards compat with old 7-element replies
  if {[info exists result] && [llength $result] >= 7} {
    set sessionStatus [ lindex $result 3 ]
    set mitata [ lindex $result 5 ]
    # Extract fingerprint to forward to ingest for non-mitigated requests
    if {[llength $result] >= 8} {
      set headerFingerprint [ lindex $result 7 ]
    } else {
      set headerFingerprint ""
    }
  } else {
    set sessionStatus ""
    set mitata ""
    # Default empty when handleRequest was not called or failed
    set headerFingerprint ""
  }
  # Forward fingerprint at index 11 so ingest logs it as HeaderHash
  if {[catch {ILX::call $handle ingest $clientaddress $useragent [HTTP::status] $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time $mitata $sessionStatus $headerFingerprint} result]} {
    log local0.error  "Client - $clientaddress, ILX failure: could not reach ingest API"
    # Send user graceful error message, then exit event
    return
  }
}
