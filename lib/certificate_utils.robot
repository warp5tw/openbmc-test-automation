*** Settings ***
Documentation  Certificate utilities keywords.

Library        OperatingSystem
Resource       rest_client.robot
Resource       resource.robot


*** Keywords ***

Install Certificate File On BMC
    [Documentation]  Install certificate file in BMC using POST operation.
    [Arguments]  ${uri}  ${status}=ok  &{kwargs}

    # Description of argument(s):
    # uri         URI for installing certificate file via Redfish
    #             e.g. "/redfish/v1/AccountService/LDAP/Certificates".
    # status      Expected status of certificate installation via Redfish
    #             e.g. error, ok.
    # kwargs      A dictionary of keys/values to be passed directly to
    #             POST Request.

    Initialize OpenBMC

    ${headers}=  Create Dictionary  Content-Type=application/octet-stream
    ...  X-Auth-Token=${XAUTH_TOKEN}
    Set To Dictionary  ${kwargs}  headers  ${headers}

    ${ret}=  Post Request  openbmc  ${uri}  &{kwargs}
    ${content_json}=  To JSON  ${ret.content}
    ${cert_id}=  Set Variable If  '${ret.status_code}' == '${HTTP_OK}'  ${content_json["Id"]}  -1

    Run Keyword If  '${status}' == 'ok'
    ...  Should Be Equal As Strings  ${ret.status_code}  ${HTTP_OK}
    ...  ELSE IF  '${status}' == 'error'
    ...  Should Be Equal As Strings  ${ret.status_code}  ${HTTP_INTERNAL_SERVER_ERROR}

    Delete All Sessions

    [Return]  ${cert_id}


Get Certificate Content From BMC Via Openssl
    [Documentation]  Get certificate content from BMC via openssl.

    Check If Openssl Tool Exist

    ${openssl_cmd}=  Catenate
    ...  timeout 10  openssl s_client -connect ${OPENBMC_HOST}:443 -showcerts
    ${output}=  Run  ${openssl_cmd}

    ${result}=  Fetch From Left
    ...  ${output}  -----END CERTIFICATE-----
    ${result}=  Fetch From Right  ${result}  -----BEGIN CERTIFICATE-----
    [Return]  ${result}


Get Certificate File Content From BMC
    [Documentation]  Get required certificate file content from BMC.
    [Arguments]  ${cert_type}=Client

    # Description of argument(s):
    # cert_type      Certificate type (e.g. "Client" or "CA").

    ${certificate}  ${stderr}  ${rc}=  Run Keyword If  '${cert_type}' == 'Client'
    ...    BMC Execute Command  cat /etc/nslcd/certs/cert.pem

    [Return]  ${certificate}


Generate Certificate File Via Openssl
    [Documentation]  Create certificate file via openssl with required content
    ...              and returns its path.
    [Arguments]  ${cert_format}  ${time}=365  ${cert_dir_name}=certificate_dir

    # Description of argument(s):
    # cert_format          Certificate file format
    #                      e.g. Valid_Certificate_Empty_Privatekey.
    # time                 Number of days to certify the certificate for.
    # cert_dir_name        The name of the sub-directory where the certificate
    #                      is stored.

    Check If Openssl Tool Exist

    ${openssl_cmd}=  Catenate  openssl req -x509 -sha256 -newkey rsa:2048
    ...  ${SPACE}-nodes -days ${time}
    ...  ${SPACE}-keyout ${cert_dir_name}/cert.pem -out ${cert_dir_name}/cert.pem
    ...  ${SPACE}-subj "/O=XYZ Corporation /CN=www.xyz.com"

    ${rc}  ${output}=  Run And Return RC and Output  ${openssl_cmd}
    Should Be Equal  ${rc}  ${0}  msg=${output}
    OperatingSystem.File Should Exist
    ...  ${EXECDIR}${/}${cert_dir_name}${/}cert.pem

    ${file_content}=  OperatingSystem.Get File
    ...  ${EXECDIR}${/}${cert_dir_name}${/}cert.pem
    ${result}=  Fetch From Left  ${file_content}  -----END CERTIFICATE-----
    ${cert_content}=  Fetch From Right  ${result}  -----BEGIN CERTIFICATE-----

    ${result}=  Fetch From Left  ${file_content}  -----END PRIVATE KEY-----
    ${private_key_content}=  Fetch From Right  ${result}  -----BEGIN PRIVATE KEY-----

    ${cert_data}=
    ...  Run Keyword if  '${cert_format}' == 'Valid Certificate Valid Privatekey'
    ...  OperatingSystem.Get File  ${EXECDIR}${/}${cert_dir_name}${/}cert.pem
    ...  ELSE IF  '${cert_format}' == 'Empty Certificate Valid Privatekey'
    ...  Remove String  ${file_content}  ${cert_content}
    ...  ELSE IF  '${cert_format}' == 'Valid Certificate Empty Privatekey'
    ...  Remove String  ${file_content}  ${private_key_content}
    ...  ELSE IF  '${cert_format}' == 'Empty Certificate Empty Privatekey'
    ...  Remove String  ${file_content}  ${cert_content}  ${private_key_content}
    ...  ELSE IF  '${cert_format}' == 'Expired Certificate'
    ...  OperatingSystem.Get File  ${EXECDIR}${/}${cert_dir_name}${/}cert.pem
    ...  ELSE IF  '${cert_format}' == 'Valid Certificate'
    ...  Remove String  ${file_content}  ${private_key_content}
    ...  -----BEGIN PRIVATE KEY-----  -----END PRIVATE KEY-----
    ...  ELSE IF  '${cert_format}' == 'Empty Certificate'
    ...  Remove String  ${file_content}  ${cert_content}
    ...  ${private_key_content}  -----BEGIN PRIVATE KEY-----
    ...  -----END PRIVATE KEY-----

    ${random_name}=  Generate Random String  8
    ${cert_name}=  Catenate  SEPARATOR=  ${random_name}  .pem
    Create File  ${cert_dir_name}/${cert_name}  ${cert_data}

    [Return]  ${EXECDIR}${/}${cert_dir_name}${/}${cert_name}


Get Certificate Content From File
    [Documentation]  Get certificate content from certificate file.
    [Arguments]  ${cert_file_path}

    # Description of argument(s):
    # cert_file_path  Downloaded certificate file path.

    ${file_content}=  OperatingSystem.Get File  ${cert_file_path}
    ${result}=  Fetch From Left  ${file_content}  -----END CERTIFICATE-----
    ${result}=  Fetch From Right  ${result}  -----BEGIN CERTIFICATE-----
    [Return]  ${result}


Check If Openssl Tool Exist
    [Documentation]  Check if openssl tool installed or not.

    ${rc}  ${output}=  Run And Return RC and Output  which openssl
    Should Not Be Empty  ${output}  msg=Openssl tool not installed.


Verify Certificate Visible Via OpenSSL
    [Documentation]  Checks if given certificate is visible via openssl's showcert command.
    [Arguments]  ${cert_file_path}

    # Description of argument(s):
    # cert_file_path           Certificate file path.

    ${cert_file_content}=  OperatingSystem.Get File  ${cert_file_path}
    ${openssl_cert_content}=  Get Certificate Content From BMC Via Openssl
    Should Contain  ${cert_file_content}  ${openssl_cert_content}

