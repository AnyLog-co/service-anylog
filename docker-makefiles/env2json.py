import os
import ast
import json

ROOT_DIR =  os.path.dirname(__file__).split("docker-makefiles")[0]
SERVICE_DEFINITION = os.path.join(ROOT_DIR, "service.definition.json")
if not os.path.isfile(SERVICE_DEFINITION):
    raise FileNotFoundError(SERVICE_DEFINITION)
SERVICE_POLICY     = os.path.join(ROOT_DIR, "service.policy.json")
if not os.path.isfile(SERVICE_POLICY):
    raise FileNotFoundError(SERVICE_POLICY)
NODE_POLICY        = os.path.join(ROOT_DIR, "node.policy.json")
if not os.path.isfile(NODE_POLICY):
    raise FileNotFoundError(NODE_POLICY)

INPUT_DIR = os.path.join(ROOT_DIR, "docker-makefiles", "anylog-generic") # <-- user defined input
if not os.path.isdir(INPUT_DIR):
    raise NotADirectoryError(INPUT_DIR)
INPUT_ENV = os.path.join(INPUT_DIR, "node_configs.env")
if not os.path.isfile(INPUT_ENV):
    raise FileNotFoundError(INPUT_ENV)

OUTPUT_SERVICE_DEFINITION = os.path.join(INPUT_DIR, "service.definition.json")
OUTPUT_SERVICE_POLICY     = os.path.join(INPUT_DIR, "service.policy.json")
OUTPUT_NODE_POLICY        = os.path.join(INPUT_DIR, "node.policy.json")

def read_env():
    configs = []
    comment = ""
    param = None
    value = None
    with open(INPUT_ENV, 'r') as f:
        for line in f.readlines():
            if line.strip():
                if line.startswith("#===") or line.startswith("#---"):
                   pass
                elif line.startswith('#'):
                    comment += line.strip()
                elif '=' in line:
                    param, value = line.split("=", 1)
            if comment and param and value:
                value = value.replace('\n', '').strip()
                if value:
                    try:
                        value = ast.literal_eval(value)
                    except:
                        pass

                value_type = "string"
                if isinstance(value, (int, float)):
                    value_type = "int"

                configs.append({
                    "name": param,
                    "label": comment.replace('#', '').replace('\n', ' ').strip(),
                    "type": value_type,
                    "value": value
                })
                comment = ""
                param = None
                value = None

    return configs

def update_service_definition(configs:list):
    with open(SERVICE_DEFINITION, 'r') as f:
        file_content = json.load(f)
    file_content["userInput"] = configs

    with open(OUTPUT_SERVICE_DEFINITION, 'w') as f:
        json.dump(file_content, f, indent=2)

def update_service_policy(node_name:str):
    with open(SERVICE_POLICY, 'r') as f:
        file_content = json.load(f)
    file_content["constraints"] = [f"openhorizon.allowPrivileged == true AND purpose == {node_name}"]

    with open(OUTPUT_SERVICE_POLICY, 'w') as f:
        json.dump(file_content, f, indent=2)

def update_node_policy(node_name: str):
    with open(NODE_POLICY, 'r') as f:
        file_content = json.load(f)


    if file_content.get("properties") is not None:
        for index in range(len(file_content["properties"])):
            if file_content["properties"][index].get("name") == "purpose":
                file_content["properties"][index]["value"] = node_name

    with open(OUTPUT_NODE_POLICY, 'w') as f:
        json.dump(file_content, f, indent=2)


def main():
    configs = read_env()
    node_name = "anylog-node"
    for config in configs:
        if "NODE_NAME" in list(config.values()):
            node_name = config.get("value")
            break

    update_service_definition(configs=configs)
    update_service_policy(node_name=node_name)
    update_node_policy(node_name=node_name)


if __name__ == "__main__":
    main()