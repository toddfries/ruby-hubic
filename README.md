Hubic
=====

Requirement
-----------
You need to retrieve the client id, secret key, and redirection url. 
For that if not already done you need to register an application into
your account. 
To start the registration process you will need to go to ``My Account``,
select ``Your application``, and click on ``Add an application``.

Quick example
-------------
From the commande line:

```sh
HUBIC_USER=foo@bar.com                  # Set the user on which we will act
hubic client   config                   # Configure the client API key
hubic auth                              # Authenticate the user
hubic mkdir    cloud                    # Create directory
hubic upload   file.txt cloud/file.txt  # Upload file
hubic md5      cloud/file.txt           # Retrieve MD5
hubic download cloud/file.txt           # Download file
hubic delete   cloud/file.txt           # Remove file
```

From a ruby script:
```ruby
require 'hubic'

# Configure the client 
Hubic.default_redirect_uri  = '** your redirect_uri  **'
Hubic.default_client_id     = '** your client_id     **'
Hubic.default_client_secret = '** your client_secret **'

# Create a hubic handler for the desired user
h = Hubic.for_user('** your login **', '** your password **')

# Download file hubic-foo.txt and save it to local-foo.txt
h.download("hubic-foo.txt", "local-foo.txt")

# Upload file local-foo.txt and save it to hubic with the name hubic-bar.txt
h.upload("local-foo.txt", "hubic-bar.txt")
```


HUBIC_USER=jml@finexkap.com


SSL issues
----------
in case you get such an error
``connect': SSL_connect returned=1 errno=0 state=SSLv3 read server certificate B: certificate verify failed (Faraday::SSLError)``
here is the solution
http://meeech.amihod.com/troubleshooting-ssl-cert-with-rbenvruby-193/

basically you need to 
``curl http://curl.haxx.se/ca/cacert.pem > cacert.pem``

And then
```sh
export SSL_CERT_FILE=~/cacert.pem
```