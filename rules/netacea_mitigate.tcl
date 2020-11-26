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
    if { [HTTP::path] equals "/AtaVerifyCaptcha" && [string tolower $method] eq "post"} {  # Handle Captcha tests
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
        # set result [ILX::call $handle check [IP::client_addr] $useragent [HTTP::method] [HTTP::uri] [HTTP::cookie value "_mitata"] [HTTP::cookie value "_mitatacaptcha"]]
        if {[catch {ILX::call $handle handleRequest [IP::client_addr] $useragent $method [HTTP::path] [HTTP::cookie value "_mitata"] [HTTP::cookie value "_mitatacaptcha"]} result]} {
           log local0.error  "Client - [IP::client_addr], ILX failure: could not reach mitigate API: $result"
           # Send user graceful error message, then exit event
           return
        }

        if {[info exists result] && [llength $result] == 7}{
            set body  [ lindex $result 0 ]
            set apiCallStatus [ lindex $result 1 ]
            set cookies [ lindex $result 2 ]
            set sessionStatus [ lindex $result 3 ]
            set mitigated [ lindex $result 4 ]
            set mitata [ lindex $result 5 ]
            set injectHeaders [ lindex $result 6]
            set ilx_request_time [clock clicks -milliseconds]
            set HTTP::mitata $mitata
            set HTTP::sessionStatus $sessionStatus

            if { $mitigated } then {
              # calcluate request time
              set http_response_time [clock clicks -milliseconds]
              set request_time [ expr $http_response_time - $http_request_time ]
              ILX::call $handle ingest [IP::client_addr] $useragent 403 $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time $mitata $sessionStatus
              HTTP::respond 403 content $body Set-Cookie [join $cookies "; "]
            }
            if { [llength $injectHeaders] == 3} {
              HTTP::header insert "x-netacea-match" [ lindex $injectHeaders 0 ]
              HTTP::header insert "x-netacea-mitigate" [ lindex $injectHeaders 1 ]
              HTTP::header insert "x-netacea-captcha" [ lindex $injectHeaders 2 ]
            }
        }
    }
}

when HTTP_REQUEST_DATA {
    if { [HTTP::path] equals "/AtaVerifyCaptcha" && [string tolower $method] eq "post"} {  # Handle Captcha tests
        set method [HTTP::method]
        set uri [HTTP::uri]
        set useragent [HTTP::header value "User-Agent"]

        # set result [ILX::call $handle handleCaptcha [IP::client_addr] [HTTP::header value "User-Agent"] [HTTP::cookie value "_mitata"] [HTTP::payload]]
        if {[catch {ILX::call $handle handleRequest [IP::client_addr] $useragent $method [HTTP::path] [HTTP::cookie value "_mitata"] [HTTP::cookie value "_mitatacaptcha"] [HTTP::payload]} result]} {
           log local0.error  "Client - [IP::client_addr], ILX failure: could not handle captcha test"
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
        foreach cookie $cookies {
          HTTP::header insert "Set-Cookie" $cookie
        }

        # calcuate request time
        set http_response_time [clock clicks -milliseconds]
        set request_time [ expr $http_response_time - $http_request_time ]

        # ILX::call $handle ingest [IP::client_addr] $useragent 200 $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time $mitata $sessionStatus
        if {[catch {ILX::call $handle ingest [IP::client_addr] $useragent 403 $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time $mitata $sessionStatus} result]} {
            log local0.error  "Client - [IP::client_addr], ILX failure: could not reach ingest API for passed captcha"
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

    # calcluate request time
    set http_response_time [clock clicks -milliseconds]
    set request_time [ expr $http_response_time - $http_request_time ]

    # ILX::call $handle ingest [IP::client_addr] $useragent [HTTP::status] $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time $mitata $sessionStatus
    if {[catch {ILX::call $handle ingest [IP::client_addr] $useragent [HTTP::status] $method $uri "http" $referer [HTTP::header value "Content-Length"] $request_time HTTP::mitata HTTP::sessionStatus} result]} {
       log local0.error  "Client - [IP::client_addr], ILX failure: could not reach ingest API"
       # Send user graceful error message, then exit event
       return
    }
}

