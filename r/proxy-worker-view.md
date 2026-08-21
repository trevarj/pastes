 systemd-run fits goal better: confine host-native Pi, not build portable dev environment.
                                                                                                                 
 - Uses Nix-pinned host tools directly. No container image or duplicated dependency setup.                       
 - Starts fast. No Docker/Podman daemon, image pull, build, or lifecycle.                                        
 - Fine-grained allowlist: writable ~/Workspace, Pi state, read-only Nix store/config, selected SSH/GPG agent    
   sockets.                                                                                                      
 - Strong native controls: private PID/tmp/device namespaces, hidden home, dropped capabilities,                 
   syscall/filesystem protections.                                                                               
 - Keeps Nix daemon, Ollama loopback, terminal PTY, signed commits, and SSH pushes working with narrow exposure. 
 - Sandbox contract tested by scripts/pi-sandbox-check.sh.                                                       
                                                                                                                 
 Devcontainers optimize reproducible editor environments. They are not automatically stronger sandboxes and      
 would add image/runtime/config complexity. Use one if cross-platform onboarding or non-Nix toolchain            
 reproducibility becomes goal. 