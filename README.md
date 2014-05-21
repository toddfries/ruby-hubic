Hubic
=====

Requirement
-----------
You need to retrieve the client id, secret key, and redirection url. 
For that if not alredy done you need to register an application into your account. 
To start the registration process you will need to go to ``My Account``, select ``Your application``, and click on ``Add an application``.

Quick example
-------------
```sh
HUBIC_USER=foo@bar.com
hubic client   config
hubic auth
hubic upload   local-file.txt documents/cloud-file.txt
hubic download documents/cloud-file.txt
hubic delete   documents/cloud-file.txt
```


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


