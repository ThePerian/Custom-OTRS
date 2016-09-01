#!/usr/bin/env python
import sys
import os
import json
from suds.client import Client

configPath = os.path.dirname(__file__)
if not configPath.endswith("/") and configPath <> "":
    configPath += "/"
config = json.load(open(configPath + "config.json"))

for item in config:
    config[item] = config[item].decode().encode('utf8')

client = Client(config["wsdl_main"], username=config["login_main"], password=config["password_main"])
result = client.service.GetCard(CodeTO=sys.argv[1])
print result
