when RULE_INIT {
  # Initialize header policy variables.
  # Actual fetch deferred to first HTTP_REQUEST (ILX::init not available in RULE_INIT).
  set static::mitigation_headers {}
  set static::mitigation_headers_loaded 0
  set static::mitigation_headers_fetch_attempts 0
  set static::mitigation_headers_max_attempts 3
  log local0.debug "Netacea RULE_INIT: iRule loaded (v2 with header policy support)"
}

when HTTP_REQUEST {
  set http_request_time [clock clicks -milliseconds]
  if {[catch {ILX::init "Netacea" "netacea"} handle]} {
    log local0.error  "Client - [IP::client_addr], ILX failure: could not reach ILX plugin - make sure it is running in the ILX plugin console"
    # Send user graceful error message, then exit event
    set error 1
    return
  }

  # Fetch header policy on first request (ILX::init not available in RULE_INIT)
  if { !$static::mitigation_headers_loaded } {
    if { $static::mitigation_headers_fetch_attempts < $static::mitigation_headers_max_attempts } {
      incr static::mitigation_headers_fetch_attempts
      if {[catch {ILX::call $handle getMitigationHeaderPolicy} policyResult]} {
        log local0.error "Client - [IP::client_addr], ILX failure: could not fetch mitigation header policy (attempt $static::mitigation_headers_fetch_attempts): $policyResult"
        # After max attempts, stop retrying - requests proceed with empty header policy
        if { $static::mitigation_headers_fetch_attempts >= $static::mitigation_headers_max_attempts } {
          log local0.warn "Client - [IP::client_addr], Netacea policy: max attempts reached, proceeding with empty header policy"
          set static::mitigation_headers_loaded 1
        }
      } else {
        log local0.debug "Client - [IP::client_addr], Netacea policy: getMitigationHeaderPolicy returned: $policyResult"
        # Guard against empty policy reply: split "" "," returns {""}
        set splitResult [split $policyResult ","]
        if { [llength $splitResult] == 1 && [lindex $splitResult 0] eq "" } {
          log local0.warn "Client - [IP::client_addr], Netacea policy: empty policy reply from worker"
        } else {
          set static::mitigation_headers $splitResult
        }
        set static::mitigation_headers_loaded 1
        log local0.debug "Client - [IP::client_addr], Netacea policy: loaded [llength $static::mitigation_headers] headers: $static::mitigation_headers"
      }
    }
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
      if { [HTTP::header "Content-Length"] > 64000 } {
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
        # Collect header values based on policy — each value individually base64-encoded
        set headerValuesList {}
        foreach hdr $static::mitigation_headers {
          lappend headerValuesList [b64encode [HTTP::header value $hdr]]
        }
        set headerValues [join $headerValuesList ","]

        if {[catch {ILX::call $handle handleRequest $clientaddress $method [HTTP::uri] "" $headerNames $headerValues} result]} {
          log local0.error  "Client - $clientaddress, ILX failure: could not reach mitigate API: $result"
          # Send user graceful error message, then exit event
          return
        }

    if {[info exists result] && [llength $result] >= 8} {
      set body [lindex $result 0]
      set apiCallStatus [lindex $result 1]
      set sessionStatus [lindex $result 2]
      set mitigated [lindex $result 3]
      set mitata [lindex $result 4]
      set headerFingerprint [lindex $result 5]
      set requestHeaders [lindex $result 6]
      set responseHeaders [lindex $result 7]

      # Set inject headers on request (dynamic — no hardcoded names)
      foreach {hname hval} $requestHeaders {
        HTTP::header insert $hname [b64decode $hval]
      }

      if { $mitigated } then {
        # calculate request time
        set http_response_time [clock clicks -milliseconds]
        set request_time [expr {$http_response_time - $http_request_time}]
        log local0.debug "Client - $clientaddress, Netacea mitigate: MITIGATED 403, request_time=${request_time}ms"
        ILX::call $handle ingest $clientaddress $useragent 403 $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time $mitata $sessionStatus $headerFingerprint

        # Build HTTP::respond dynamically from responseHeaders
        set respondArgs [list HTTP::respond 403 content $body]
        foreach {hname hval} $responseHeaders {
          lappend respondArgs $hname [b64decode $hval]
        }
        eval $respondArgs
      }
    } else {
      log local0.warn "Client - $clientaddress, Netacea mitigate: unexpected result length [llength $result], expected >= 8"
    }
  }
}

when HTTP_REQUEST_DATA {
  if {![info exists handle]} { return }

  if { [HTTP::path] equals "/AtaVerifyCaptcha" && [string tolower [HTTP::method]] eq "post"} {
    set method [HTTP::method]
    set uri [HTTP::uri]
    set useragent [HTTP::header value "User-Agent"]
    set referer [HTTP::header value "referer"]
    # strip route domain from ip
    set clientaddress [regsub {%.*} [IP::client_addr] ""]

    if {![info exists http_request_time]} {
      set http_request_time [clock clicks -milliseconds]
    }

    # Collected again because HTTP_REQUEST_DATA is a separate event
    set headerNames [join [HTTP::header names] ","]

    # Guard mitigation headers policy
    if { !$static::mitigation_headers_loaded || [llength $static::mitigation_headers] == 0 } {
      log local0.warn "Client - $clientaddress, Netacea captcha: mitigation headers not loaded, proceeding with empty header values"
    }

    # Collect header values based on policy — each value individually base64-encoded
    set headerValuesList {}
    foreach hdr $static::mitigation_headers {
      lappend headerValuesList [b64encode [HTTP::header value $hdr]]
    }
    set headerValues [join $headerValuesList ","]

    if {[catch {ILX::call $handle handleRequest $clientaddress $method [HTTP::path] [HTTP::payload] $headerNames $headerValues} result]} {
      log local0.error  "Client - $clientaddress, ILX failure: could not handle captcha test"
      # Send user graceful error message, then exit event
      return
    }

    if {[llength $result] < 8} {
      log local0.warn "Client - $clientaddress, Netacea captcha: unexpected result length [llength $result], expected >= 8"
      return
    }

    set body [lindex $result 0]
    set apiCallStatus [lindex $result 1]
    set sessionStatus [lindex $result 2]
    set mitigated [lindex $result 3]
    set mitata [lindex $result 4]
    set headerFingerprint [lindex $result 5]
    set requestHeaders [lindex $result 6]
    set responseHeaders [lindex $result 7]

    log local0.debug "Client - $clientaddress, Netacea captcha: sessionStatus=$sessionStatus mitigated=$mitigated fingerprint=$headerFingerprint"

    set http_response_time [clock clicks -milliseconds]
    set request_time [expr {$http_response_time - $http_request_time}]
    if {[catch {ILX::call $handle ingest $clientaddress $useragent 403 $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time $mitata $sessionStatus $headerFingerprint} ingestResult]} {
      log local0.error "Client - $clientaddress, ILX failure: could not reach ingest API for captcha"
    }

    # Build HTTP::respond dynamically
    set respondArgs [list HTTP::respond 403 content $body]
    foreach {hname hval} $responseHeaders {
      lappend respondArgs $hname [b64decode $hval]
    }
    eval $respondArgs
  }
}

when HTTP_RESPONSE {
  # Set response headers from worker reply (e.g. Set-Cookie)
  if {[info exists responseHeaders]} {
    foreach {hname hval} $responseHeaders {
      HTTP::header insert $hname [b64decode $hval]
    }
  }
  set clientaddress [regsub {%.*} [IP::client_addr] ""]

  # Guard handle — if ILX::init failed in HTTP_REQUEST, skip ingest
  if {![info exists handle]} {
    return
  }

  # Guard http_request_time
  if {![info exists http_request_time]} {
    set http_request_time [clock clicks -milliseconds]
  }

  # Guard cross-event variables with re-computation
  if {![info exists method]} { set method [HTTP::method] }
  if {![info exists uri]} { set uri [HTTP::uri] }
  if {![info exists useragent]} { set useragent [HTTP::header value "User-Agent"] }
  if {![info exists referer]} { set referer [HTTP::header value "referer"] }

  # calculate request time
  set http_response_time [clock clicks -milliseconds]
  set request_time [expr {$http_response_time - $http_request_time}]

  if {[info exists result] && [llength $result] >= 8} {
    set sessionStatus [lindex $result 2]
    set mitata [lindex $result 4]
    set headerFingerprint [lindex $result 5]
  } else {
    set sessionStatus ""
    set mitata ""
    set headerFingerprint ""
  }
  if {[catch {ILX::call $handle ingest $clientaddress $useragent [HTTP::status] $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time $mitata $sessionStatus $headerFingerprint} result]} {
    log local0.error  "Client - $clientaddress, ILX failure: could not reach ingest API"
    # Send user graceful error message, then exit event
    return
  }
}
