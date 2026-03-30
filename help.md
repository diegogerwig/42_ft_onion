# ft_onion — Guía Explicativa

Guía técnica completa. Cubre la arquitectura, el propósito de cada archivo y los puntos clave.

---

## Arquitectura general

```
                    INTERNET / TOR NETWORK
                           │
                    [Tor Browser / torsocks]
                           │
                    ┌──────▼──────┐
                    │  Tor daemon │   ← gestiona la identidad .onion
                    │ (debian-tor)│
                    └──────┬──────┘
                           │
              ┌────────────┴────────────┐
              │                         │
        puerto 80                  puerto 4242
              │                         │
       ┌──────▼──────┐         ┌────────▼────────┐
       │    Nginx    │         │   OpenSSH sshd  │
       │  (HTTP web) │         │  (acceso shell) │
       └──────┬──────┘         └────────┬────────┘
              │                         │
         index.html               onionuser
              │                  (solo clave ED25519)
        /var/www/html
```

Todo el tráfico entra y sale exclusivamente por la red Tor. **No hay ningún puerto expuesto al host** (`docker run` sin `-p`), lo cual es un requisito explícito del subject.

---

## Flujo de arranque

Cuando se ejecuta `make all`, ocurre lo siguiente en orden:

1. **`make onion_key`** — Genera el par de claves ED25519 en `conf/` si no existen.
2. **`docker build`** — Construye la imagen copiando configuraciones y compilando la imagen base Debian.
3. **`docker run -d`** — Lanza el contenedor en segundo plano.
4. **`entrypoint.sh`** — Dentro del contenedor, arranca `sshd`, `nginx` y `tor` en ese orden.
5. **Bootstrap de Tor (~10s)** — Tor genera la clave del hidden service, escribe la dirección `.onion` en `/var/lib/tor/hidden_service/hostname` y establece el circuito.
6. **`make onion`** — Lee y muestra la dirección `.onion` generada.

---

## Archivos del proyecto

### `Dockerfile`

Define la imagen del contenedor a partir de `debian:bullseye-slim`.

**Paquetes instalados:**

| Paquete | Función |
|---|---|
| `nginx` | Servidor web que sirve `index.html` |
| `tor` | Crea el túnel de red anónimo y gestiona la dirección `.onion` |
| `openssh-server` | Daemon SSH accesible por la red Tor |
| `openssh-client` | Permite hacer `ssh` desde dentro del contenedor (test local) |

**Puntos clave:**

```dockerfile
RUN useradd -m -s /bin/bash onionuser
```
- `-m` → crea `/home/onionuser/`, necesaria para el directorio `.ssh`
- `-s /bin/bash` → shell funcional al conectar por SSH

```dockerfile
RUN chmod 700 /home/onionuser/.ssh
RUN chmod 600 /home/onionuser/.ssh/authorized_keys
```
- `700` → solo el propietario puede entrar al directorio (SSH lo rechaza si es más permisivo)
- `600` → solo lectura/escritura del propietario sobre las claves (requisito estricto de OpenSSH)

```dockerfile
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh
```
- Elimina los retornos de carro de Windows (`\r`) que romperían el script en Linux si el archivo se editó en Windows.

```dockerfile
RUN ssh-keygen -A
```
- Genera las claves del host SSH (`/etc/ssh/ssh_host_*`). Sin esto, `sshd` no puede arrancar.

---

### `src/entrypoint.sh`

Script de arranque que se ejecuta al iniciar el contenedor.

```bash
#!/bin/bash

mkdir -p /run/sshd           # Directorio PID requerido por sshd

/usr/sbin/sshd               # Arranca SSH en primer plano brevemente, luego se daemoniza solo

nginx &                      # Nginx en segundo plano (daemon off; en nginx.conf lo requiere)

su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc" &   # Tor como usuario sin privilegios

echo "Waiting for the Tor network to bootstrap..."

sleep 10                     # Tiempo para que Tor establezca el circuito

tail -f /dev/null            # Mantiene el contenedor vivo indefinidamente
```

**Por qué `tail -f /dev/null`:** Docker termina el contenedor si el proceso principal (PID 1 = entrypoint.sh) acaba. Como los servicios corren en background con `&`, el script llegaría al final y mataría todo. Este comando bloquea para siempre leyendo un archivo vacío, manteniendo el contenedor activo.

**Por qué Tor corre como `debian-tor`:** Tor tiene protecciones internas que le impiden arrancar como root. `debian-tor` es el usuario sin privilegios creado automáticamente al instalar el paquete en Debian.

---

### `conf/torrc`

Configuración del daemon Tor.

```
HiddenServiceDir /var/lib/tor/hidden_service/
HiddenServicePort 80 127.0.0.1:80
HiddenServicePort 4242 127.0.0.1:4242
```

- **`HiddenServiceDir`** → Tor guarda aquí la clave privada del hidden service y el archivo `hostname` con la dirección `.onion`. El directorio debe pertenecer a `debian-tor` con permisos `700`.
- **`HiddenServicePort`** → Actúa como proxy inverso interno: todo el tráfico que llega por la red Tor al puerto indicado se redirige a `localhost` en ese mismo puerto.

> **Punto de defensa:** La dirección `.onion` es un hash criptográfico derivado de la clave pública del hidden service, no una IP. Es estable mientras no se elimine el contenedor (o la carpeta del hidden service).

---

### `conf/sshd_config`

Configuración del daemon SSH con hardening de seguridad.

```
Port 4242
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
AllowUsers onionuser
```

| Directiva | Motivo de seguridad |
|---|---|
| `Port 4242` | Requerido por el subject. Evita bots que escanean el puerto 22 |
| `PermitRootLogin no` | Impide que un atacante tome control total del sistema |
| `PasswordAuthentication no` | Elimina ataques de fuerza bruta / diccionario |
| `PubkeyAuthentication yes` | Solo se entra con la clave criptográfica correcta |
| `AllowUsers onionuser` | Lista blanca: cualquier otro usuario del sistema es rechazado |

---

### `conf/nginx.conf`

Configuración del servidor web.

```nginx
daemon off;
```

> **Punto clave:** Por defecto Nginx se desacopla de la terminal y se ejecuta en background. En Docker, si el proceso desaparece de la vista del PID manager, el contenedor puede pensar que falló. `daemon off;` fuerza a Nginx a quedarse en primer plano, controlado por el `&` del entrypoint.

El servidor escucha en `0.0.0.0:80` y sirve `/var/www/html/index.html`. Tor redirige el tráfico `.onion:80` a este puerto internamente.

---

### `conf/index.html`

Página estática servida a través del hidden service. Diseño minimalista con tema oscuro y fuente monoespaciada, coherente con el entorno de red Tor.

---

### `Makefile`

Panel de control del proyecto.

| Regla | Descripción |
|---|---|
| `make all` | Construye, arranca, espera 10s, muestra logs y dirección `.onion` |
| `make build` | Genera claves SSH si no existen y construye la imagen sin caché |
| `make run` | Arranca el contenedor en segundo plano |
| `make onion` | Imprime la dirección `.onion` activa |
| `make test-ssh-tor` | Conecta por SSH a través de Tor (requiere `torsocks` en el host) |
| `make test-ssh-local` | Conecta por SSH a `127.0.0.1:4242` dentro del contenedor (sin Tor) |
| `make clean` | Para y elimina el contenedor |
| `make fclean` | Elimina contenedor, imagen y claves generadas |
| `make re` | Reconstrucción completa desde cero |

**Generación de claves:**

```bash
ssh-keygen -t ed25519 -f conf/onion_key -q -N ""
```

| Flag | Significado |
|---|---|
| `-t ed25519` | Algoritmo moderno, más seguro y compacto que RSA |
| `-f conf/onion_key` | Ruta de salida (genera `onion_key` y `onion_key.pub`) |
| `-q` | Modo silencioso, sin arte ASCII |
| `-N ""` | Sin passphrase, para no requerir contraseña al usar la clave |

**Comando de conexión SSH por Tor:**

```bash
torsocks ssh -i conf/onion_key \
             -o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             -p 4242 \
             onionuser@<address>.onion
```

| Flag | Motivo |
|---|---|
| `torsocks` | Enruta la conexión SSH por el proxy Tor local |
| `-i conf/onion_key` | Identidad (clave privada) a usar |
| `StrictHostKeyChecking=no` | No pregunta confirmación en la primera conexión |
| `UserKnownHostsFile=/dev/null` | No guarda la huella del host; evita el error MITM al reconstruir el contenedor |
| `-p 4242` | Puerto SSH no estándar definido en `sshd_config` |

---

## Referencia completa de flags por comando

### `ssh-keygen` — Generación de claves SSH

```bash
# Makefile: genera el par de claves del usuario
ssh-keygen -t ed25519 -f conf/onion_key -q -N ""

# Dockerfile: genera las claves del host SSH
ssh-keygen -A
```

| Flag | Valor | Descripción |
|---|---|---|
| `-t` | `ed25519` | Tipo de algoritmo criptográfico. ED25519 (curva elíptica) es más seguro, más rápido y genera claves más cortas que RSA-4096. Resistente a ataques de canal lateral. |
| `-f` | `conf/onion_key` | Fichero (file) de salida. Genera dos archivos: `onion_key` (clave privada) y `onion_key.pub` (clave pública). |
| `-q` | — | Quiet: modo silencioso. Suprime el arte ASCII y los mensajes informativos del proceso de generación. |
| `-N` | `""` | Nueva passphrase vacía. Permite usar la clave sin introducir contraseña, necesario para automatización en scripts. |
| `-A` | — | Genera automáticamente todos los tipos de claves de host que faltan (`rsa`, `ecdsa`, `ed25519`) con sus rutas por defecto en `/etc/ssh/`. Requerido para que `sshd` pueda arrancar. |

---

### `docker build` — Construcción de la imagen

```bash
docker build --no-cache -t ft_onion .
```

| Flag | Valor | Descripción |
|---|---|---|
| `--no-cache` | — | Ignora la caché de capas de Docker. Fuerza la reconstrucción completa desde cero. Garantiza que los cambios en archivos copiados (`COPY`) se apliquen siempre. |
| `-t` | `ft_onion` | Tag (etiqueta) que asigna un nombre a la imagen resultante. Sin este flag, la imagen solo sería accesible por su hash SHA256. |
| `.` | — | Contexto de construcción: el directorio actual. Docker envía este directorio al daemon para ejecutar el `Dockerfile`. |

---

### `docker run` — Inicio del contenedor

```bash
docker run -d --name my_onion ft_onion
```

| Flag | Valor | Descripción |
|---|---|---|
| `-d` | — | Detached: ejecuta el contenedor en segundo plano y devuelve el control de la terminal inmediatamente. Sin este flag, el terminal quedaría bloqueado mostrando los logs. |
| `--name` | `my_onion` | Asigna un nombre fijo al contenedor. Sin esto, Docker genera un nombre aleatorio. El nombre se usa en `docker exec`, `docker logs`, `docker rm`. |
| (sin `-p`) | — | Ausencia deliberada. No se mapea ningún puerto al host. Todo el tráfico entra por la red Tor. Requisito explícito del subject. |

---

### `docker exec` — Ejecución de comandos en el contenedor

```bash
docker exec my_onion cat /var/lib/tor/hidden_service/hostname
docker exec -it my_onion ssh -i /tmp/onion_key_tmp ... onionuser@127.0.0.1
docker exec my_onion chmod 600 /tmp/onion_key_tmp
docker exec my_onion rm -f /tmp/onion_key_tmp
```

| Flag | Descripción |
|---|---|
| `-i` | Interactive: mantiene STDIN abierto aunque no esté conectado a una terminal. Necesario para sesiones SSH interactivas. |
| `-t` | TTY: asigna una pseudo-terminal al proceso. Sin esto, la sesión SSH no renderiza el prompt correctamente. |
| `-it` | Combinación habitual de `-i` y `-t` para sesiones interactivas con shell. |

---

### `docker cp` — Copia de archivos al contenedor

```bash
docker cp conf/onion_key my_onion:/tmp/onion_key_tmp
```

| Argumento | Descripción |
|---|---|
| `conf/onion_key` | Ruta de origen en el host. |
| `my_onion:/tmp/onion_key_tmp` | Destino: `nombre_contenedor:ruta_interna`. Copia el archivo directamente al sistema de ficheros del contenedor en ejecución. |

---

### `docker rm` / `docker rmi` — Eliminación

```bash
docker rm -f my_onion
docker rmi -f ft_onion
```

| Comando | Flag | Descripción |
|---|---|---|
| `docker rm` | `-f` | Force: fuerza la eliminación del contenedor aunque esté en ejecución (equivale a `docker stop` + `docker rm`). |
| `docker rmi` | `-f` | Force: elimina la imagen incluso si hay contenedores parados que la referencian. |

---

### `docker logs` — Visualización de logs

```bash
docker logs my_onion
```

Sin flags en este proyecto. Muestra todo el stdout/stderr del contenedor desde su inicio. Útil para ver si Tor arrancó correctamente y qué dirección `.onion` se asignó.

---

### `apt-get` — Gestión de paquetes (Dockerfile)

```bash
apt-get update && apt-get install -y nginx tor openssh-server openssh-client \
    && rm -rf /var/lib/apt/lists/*
```

| Subcomando / Flag | Descripción |
|---|---|
| `update` | Sincroniza el índice de paquetes con los repositorios. Siempre antes de `install`. |
| `install` | Instala los paquetes especificados y sus dependencias. |
| `-y` | Yes: responde automáticamente "sí" a todas las confirmaciones. Necesario en entornos no interactivos como `docker build`. |
| `rm -rf /var/lib/apt/lists/*` | Limpia la caché de índices descargada. Reduce el tamaño de la imagen final considerablemente. |

---

### `useradd` — Creación de usuario (Dockerfile)

```bash
useradd -m -s /bin/bash onionuser
```

| Flag | Valor | Descripción |
|---|---|---|
| `-m` | — | crea el directorio home del usuario (`/home/onionuser`). Sin esto no existe el directorio `.ssh` y SSH no puede autenticar. |
| `-s` | `/bin/bash` | Shell (intérprete de comandos) por defecto al conectar. Sin esto el usuario tendría `/bin/sh` u otro shell limitado. |

---

### `chown` — Cambio de propietario (Dockerfile)

```bash
chown -R onionuser:onionuser /home/onionuser/.ssh
chown -R debian-tor:debian-tor /var/lib/tor/hidden_service
```

| Flag | Descripción |
|---|---|
| `-R` | Recursive: aplica el cambio de propietario al directorio y todo su contenido de forma recursiva. |
| `onionuser:onionuser` | Formato `usuario:grupo`. En Linux, cada archivo tiene un propietario y un grupo. |

---

### `chmod` — Permisos de archivos (Dockerfile)

```bash
chmod 700 /home/onionuser/.ssh
chmod 600 /home/onionuser/.ssh/authorized_keys
chmod 700 /var/lib/tor/hidden_service
chmod +x /usr/local/bin/entrypoint.sh
```

Los permisos en Linux se expresan como tres dígitos octales (propietario / grupo / otros). Cada dígito es la suma de: **4** (leer) + **2** (escribir) + **1** (ejecutar).

| Valor | Binario | Permisos efectivos |
|---|---|---|
| `7` | 111 | Leer + Escribir + Ejecutar |
| `6` | 110 | Leer + Escribir |
| `0` | 000 | Sin acceso |

| Uso | Valor | Motivo |
|---|---|---|
| `.ssh/` (directorio) | `700` | Solo `onionuser` puede acceder. SSH rechaza la conexión si el grupo u otros tienen permisos. |
| `authorized_keys` | `600` | Solo `onionuser` puede leer/escribir. SSH es estricto: si el archivo es accesible por otros, ignora la clave. |
| `hidden_service/` | `700` | Solo `debian-tor` puede acceder. Tor rechaza arrancar si los permisos son más abiertos. |
| `+x` | — | Añade permiso de ejecución al script `entrypoint.sh`. Sin esto el contenedor no puede arrancarlo. |

---

### `sed` — Editor de flujo (Dockerfile)

```bash
sed -i 's/\r$//' /usr/local/bin/entrypoint.sh
```

| Flag / Expresión | Descripción |
|---|---|
| `-i` | In-place: modifica el archivo directamente en disco en lugar de imprimir el resultado por stdout. |
| `s/\r$//` | Expresión de sustitución: `s/patrón/reemplazo/`. Busca `\r` (retorno de carro, carácter Windows) al final de línea (`$`) y lo reemplaza por nada (lo elimina). |

---

### `mkdir` — Creación de directorios

```bash
mkdir -p /run/sshd
mkdir -p /home/onionuser/.ssh
mkdir -p /var/lib/tor/hidden_service
mkdir -p conf
```

| Flag | Descripción |
|---|---|
| `-p` | Parents: crea todos los directorios intermedios que no existan. No falla si el directorio ya existe. Sin `-p`, fallaría si el directorio padre no existe. |

---

### `rm` — Eliminación de archivos

```bash
rm -rf /var/lib/apt/lists/*
rm -f /tmp/onion_key_tmp
```

| Flag | Descripción |
|---|---|
| `-r` | Recursive: elimina directorios y todo su contenido de forma recursiva. |
| `-f` | Force: no muestra errores si el archivo no existe y no pide confirmación. |
| `-rf` | Combinación habitual para limpiar directorios de forma silenciosa. |

---

### `su` — Cambio de usuario (entrypoint.sh)

```bash
su -s /bin/bash debian-tor -c "tor -f /etc/tor/torrc"
```

| Flag / Argumento | Descripción |
|---|---|
| `-s /bin/bash` | Shell a usar para ejecutar el comando. Necesario porque `debian-tor` puede tener `/usr/sbin/nologin` como shell por defecto. |
| `debian-tor` | Usuario con el que se ejecuta el comando. Tor no puede correr como root. |
| `-c "..."` | Command: ejecuta la cadena como un único comando en la shell especificada. |

---

### `tor` — Daemon Tor (entrypoint.sh)

```bash
tor -f /etc/tor/torrc
```

| Flag | Descripción |
|---|---|
| `-f` | File: especifica un archivo de configuración alternativo. Sin este flag, Tor buscaría su configuración en la ruta por defecto del sistema. |

---

### `tail` — Lectura de archivos (entrypoint.sh)

```bash
tail -f /dev/null
```

| Flag | Descripción |
|---|---|
| `-f` | Follow: mantiene el archivo abierto y sigue leyendo cuando hay nuevos datos. Como `/dev/null` nunca tiene datos, el proceso queda bloqueado indefinidamente. Esto es el mecanismo que mantiene el contenedor Docker vivo. |

---

### `ssh` — Cliente SSH (Makefile: test-ssh-tor / test-ssh-local)

```bash
torsocks ssh -i /tmp/onion_key_tmp \
             -o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             -p 4242 \
             onionuser@<address>.onion
```

| Flag | Valor | Descripción |
|---|---|---|
| `-i` | `/tmp/onion_key_tmp` | Identity file: ruta a la clave privada a usar para la autenticación. |
| `-o` | `StrictHostKeyChecking=no` | Opción de configuración inline. No pregunta "Are you sure you want to continue connecting?" al conectar a un host desconocido. |
| `-o` | `UserKnownHostsFile=/dev/null` | Redirige el archivo de hosts conocidos a `/dev/null`. Evita el error de "posible MITM" cuando se reconstruye el contenedor y cambia la huella del host. |
| `-p` | `4242` | Port: puerto de destino. SSH usa el 22 por defecto; aquí se usa el 4242 definido en `sshd_config`. |

---

### `torsocks` — Proxy Tor para comandos (Makefile)

```bash
torsocks ssh ...
```

`torsocks` no tiene flags propios en este uso. Actúa como wrapper: intercepta las llamadas de red del comando siguiente y las redirige a través del proxy SOCKS5 de Tor que corre localmente en `127.0.0.1:9050`. El comando SSH cree estar hablando directamente con el servidor, pero en realidad toda la conexión viaja por la red Tor.

---

### `tr` — Transformación de texto (Makefile)

```bash
docker exec $(CONTAINER_NAME) cat /var/lib/tor/hidden_service/hostname | tr -d '\r\n'
```

| Flag | Valor | Descripción |
|---|---|---|
| `-d` | `'\r\n'` | Delete: elimina del flujo todos los caracteres indicados. Aquí elimina `\r` (retorno de carro) y `\n` (nueva línea) para que la dirección `.onion` quede en una sola línea sin caracteres extra al usarla en el comando SSH. |

---

## Preguntas frecuentes en defensa

**¿Por qué no hay `-p` en `docker run`?**
El subject lo prohíbe expresamente. El aislamiento debe ser total: ningún puerto del contenedor se expone al host. El único punto de entrada es la red Tor.

**¿Cómo se genera la dirección `.onion`?**
Tor deriva la dirección como un hash de la clave pública del hidden service (v3 onion = 56 caracteres en base32). No es una IP registrada en ningún DNS. Mientras el directorio del hidden service no se borre, la dirección es estable.

**¿Qué pasaría si alguien intenta conectarse con contraseña?**
`PasswordAuthentication no` en `sshd_config` hace que el daemon rechace ese método de autenticación directamente, sin ni siquiera procesarlo.

**¿Por qué ED25519 y no RSA?**
ED25519 usa criptografía de curva elíptica: claves más cortas, operaciones más rápidas y resistencia a ataques de canal lateral que afectan a implementaciones RSA.

**¿Cómo verías la dirección `.onion` si el Makefile no existiera?**
```bash
docker exec my_onion cat /var/lib/tor/hidden_service/hostname
```

**¿Cómo probarías que el SSH funciona sin Tor?**
```bash
make test-ssh-local
# equivale a:
docker exec -it my_onion ssh -i /tmp/onion_key_tmp -o StrictHostKeyChecking=no -p 4242 onionuser@127.0.0.1
```

**¿Por qué `sleep 10` en el entrypoint?**
Tor necesita tiempo para establecer el circuito de anonimización y registrar el hidden service en la red. Menos de 10 segundos y el `hostname` podría no estar escrito todavía.