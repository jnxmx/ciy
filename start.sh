#!/bin/bash
set -e  # Exit the script if any statement returns a non-true return value

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                #
# ---------------------------------------------------------------------------- #

# Start nginx service
start_nginx() {
    echo "Starting Nginx service..."
    service nginx start
}

# Setup SSH
setup_ssh() {
    if [[ $PUBLIC_KEY ]]; then
        echo "Setting up SSH..."
        mkdir -p ~/.ssh
        echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh

        for key_type in rsa dsa ecdsa ed25519; do
            key_path="/etc/ssh/ssh_host_${key_type}_key"
            if [ ! -f ${key_path} ]; then
                ssh-keygen -t ${key_type} -f ${key_path} -q -N ''
                echo "${key_type^^} key fingerprint:"
                ssh-keygen -lf ${key_path}.pub
            fi
        done
        
        service ssh start
        
        echo "SSH host keys:"
        for key in /etc/ssh/*.pub; do
            echo "Key: $key"
            ssh-keygen -lf $key
        done
    fi
}

# Export environment variables
export_env_vars() {
    echo "Exporting environment variables..."
    printenv | grep -E '^RUNPOD_|^PATH=|^_=' | awk -F = '{ print "export " $1 "=\"" $2 "\"" }' >> /etc/rp_environment
    echo 'source /etc/rp_environment' >> ~/.bashrc
}

# Start Jupyter Lab without password
start_jupyter() {
    echo "Starting Jupyter Lab without password..."
    mkdir -p /workspace && \
    cd / && \
    nohup jupyter lab --allow-root --no-browser --port=8888 --ip=* \
        --FileContentsManager.delete_to_trash=False \
        --ServerApp.terminado_settings='{"shell_command":["/bin/bash"]}' \
        --ServerApp.token='' \
        --ServerApp.password='' \
        --ServerApp.allow_origin=* \
        --ServerApp.preferred_dir=/workspace &> /jupyter.log &
    disown
    echo "Jupyter Lab started"
}

#nohup bash -c '
#install_sage_attention() {
#    echo "Checking for SageAttention installation..."
#    
    # Get installed version (set to 0 if not installed)
#    INSTALLED_VERSION=$(/workspace/ComfyUI/venv/bin/python -c "import sageattention; print(sageattention.__version__)" 2>/dev/null || echo "0")#
#
    # Compare versions (install if missing or below 2.0.0)
#    if [ "$INSTALLED_VERSION" != "0" ] && [ "$(printf "2.0.0\n$INSTALLED_VERSION" | sort -V | head -n1)" = "2.0.0" ]; then
#        echo "SageAttention version $INSTALLED_VERSION is already installed and up-to-date."
#    else
#        echo "Installing or updating SageAttention (current version: $INSTALLED_VERSION)..."
#        cd /workspace/SageAttention
#        /workspace/ComfyUI/venv/bin/python -m pip install --no-cache-dir -e .
#        echo "SageAttention installation completed."
#    fi
#}
#install_sage_attention' > /workspace/sageattention_install.log 2>&1 &
#disown

# Wait for ComfyUI Manager config and update security level
update_comfyui_security() {
    echo "Waiting for ComfyUI Manager config to be created..."
    while [ ! -f /workspace/ComfyUI/user/default/ComfyUI-Manager/config.ini ]; do
        sleep 1
    done
    echo "Config file detected. Setting security_level to weak..."
    sed -i 's/security_level=.*/security_level=weak/' /workspace/ComfyUI/user/default/ComfyUI-Manager/config.ini
}

# Start Filebrowser without authentication
start_filebrowser() {
    DB_PATH="/workspace/filebrowser.db"
    CONFIG_PATH="/workspace/filebrowser.json"
    cd /workspace/
    rm -f "$DB_PATH"
    rm -f "$CONFIG_PATH"

    echo "Initializing Filebrowser with command-line execution (no auth)..."
    filebrowser config init --auth.method=noauth
    filebrowser config set --commands aria2,wget,zip,unzip,ls,bash
    filebrowser config set --shell 'bash -c'

    # Important: set default permissions (scope) explicitly with execution allowed
    filebrowser users update 1 --perm.execute

    echo "Starting Filebrowser without authentication and with shell enabled..."
    nohup filebrowser -r /workspace \
        --database $DB_PATH \
        --address=0.0.0.0 \
        --port 8080 \
        --root=/workspace/ \
        --noauth &

    disown
}


# Start ComfyUI
start_comfyui() {
    echo "Starting ComfyUI..."
    cd /workspace/ComfyUI
    exec python main.py  # Keep container alive
}

# Activate virtual environment
activate_venv() {
    source /workspace/ComfyUI/venv/bin/activate
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                   #
# ---------------------------------------------------------------------------- #

# Check for CUDA availability using PyTorch
echo "Checking for CUDA availability..."
python3 -c "
import torch
if not torch.cuda.is_available():
    print('CUDA is not available. This pod is defective. Deployment is not possible.')
    exit(1)
else:
    print('CUDA is available. Proceeding with deployment.')
"

# Proceed with the rest of the startup processes
start_nginx
echo "Pod Started"

setup_ssh
start_jupyter
activate_venv
export_env_vars
start_filebrowser
# Start ComfyUI as the last command to keep the container alive
start_comfyui
