# Moodle 4.5.x Docker Környezet

## Architektúra

A projekt főbb komponensei:

1. **Moodle Alkalmazás Konténer (`moodle_app`)**:
   - Alap: `php:8.3-fpm`
   - Kiszolgáló: **Apache2** (`mpm_event` modullal és `proxy_fcgi`-vel a nagyon gyors és alacsony memóriájú kapcsolatkezelésért)
   - PHP Futtató: **PHP-FPM**
   - Folyamatkezelő: **Supervisord** (felelős az Apache és a PHP-FPM párhuzamos futtatásáért és monitorozásáért a konténeren belül)
   - PHP kiegészítők: Minden Moodle számára elvárásként megfogalmazott natív és PECL kiegészítő (pl. `pgsql`, `gd`, `intl`, `opcache`, `redis` stb.) integrálva van az image-be.

2. **Adatbázis Kapcsolatkezelő (`moodle_pgbouncer`)**:
   - **PgBouncer** a Bitnami image alapjain. Megakadályozza, hogy a Moodle és a PostgreSQL között az állandó újracsatlakozás (connention overhead) megfojtsa a rendszert.

3. **Adatbázis Kiszolgáló (`moodle_db`)**:
   - **PostgreSQL 16**.

4. **Gyorsítótár tároló (`moodle_redis`)**:
   - **Redis 7**. A Moodle Universal Cache (MUC) és a Session storage ideális helyszíne.

## Közös indítás (Docker Compose)

1. Navigálj a mappa gyökerébe a terminálban.
2. Építsd fel az image-et és indítsd el a konténereket a háttérben:
   ```bash
   docker compose up -d --build
   ```
3. A Moodle webes telepítője/megjelenítője be fog tölteni a [http://localhost:8080](http://localhost:8080) címen.

## Konfiguráció (Image Használata)

A megírt `entrypoint.sh` automatizálja a teljes PHP-FPM, Apache és PHP.ini generálást. Nem kell a képfájlt (image-et) újraépítened ahhoz, hogy skálázni vagy finomhangolni tudj; elegendő kizárólag a `docker-compose.yml` fájlod (vagy `.env` változóid) `environment` blokkját megbontani.

### 1. Hardveres Finomhangolók (Apache & PHP-FPM)
A dedikált processz limiteket az Env-ből szabályozhatod. A megfelelő beállítás kulcsfontosságú a memória és CPU hatékony kihasználásához, illetve hogy megelőzd a memóriaszivárgást (OOM - Out of Memory).

**Hogyan paraméterezz (Ökölszabályok)?**

* **Memória korlát (PHP-FPM):** 
  Egyetlen Moodle PHP-FPM munkaszál (processz) átlagosan **50-80 MB RAM**-ot fogyaszt (nehéz oldalaknál akár 100-128 MB-ot is). 
  - *Képlet:* `Rendelkezésre álló RAM (MB) / 80 = PHP_FPM_MAX_CHILDREN`
  - *Példa:* Ha a Moodle számára dedikált 4 GB RAM-od van, az 4000 MB. `4000 / 80 = 50`. Így a `PHP_FPM_MAX_CHILDREN=50` az ideális (és biztonságos) maximum.
* **CPU magok (PHP-FPM):** 
  A `PHP_FPM_START_SERVERS` és a `MIN/MAX_SPARE_SERVERS` határozza meg, mennyi szál várakozzon készenlétben. Ezeket érdemes a szerver fizikai CPU magjainak számához igazítani (pl. 4 mag = 4-8 induló, és max 16-20 várakozó szál).
* **Apache MPM Event (Webszerver):** 
  Mivel a tényleges számítási munkát a PHP-FPM végzi, az Apache feladata mindössze a proxy-zás és a statikus fájlok (JS, CSS, Képek) villámgyors kiszolgálása. Egy Apache szál nagyon alacsony memóriát eszik.
  - *Ökölszabály:* Az `APACHE_MAX_REQUEST_WORKERS` száma legyen **legalább 2-3-szorosa** a `PHP_FPM_MAX_CHILDREN`-nek. Erre azért van szükség, hogy ha minden PHP szál dolgozik, az Apache továbbra is képes legyen a statikus tartalmakat egyidejűleg kiszolgálni, és ne alakuljon ki sorban állás a weboldal betöltésekor.

**Példa egy 4 magos, 8GB RAM-os (4GB PHP dedikált) környezetre:**
- `PHP_FPM_MAX_CHILDREN=50`
- `PHP_FPM_START_SERVERS=8`
- `PHP_FPM_MIN_SPARE_SERVERS=4`
- `PHP_FPM_MAX_SPARE_SERVERS=16`
- `APACHE_MAX_REQUEST_WORKERS=150`
- `APACHE_THREADS_PER_CHILD=25`

### 2. Standard PHP paraméterek
- `PHP_MEMORY_LIMIT=512M`
- `PHP_MAX_EXECUTION_TIME=180`
- `PHP_MAX_INPUT_VARS=5000`
- `PHP_OPCACHE_MEMORY_CONSUMPTION=256`

### 3. Bármilyen egyedi `php.ini` beállítás injektálása (!)
A rendszer lehetővé teszi tetszőleges (nem felkészített) PHP direktívák bemásolását is az alábbi módszertan alapján:
Hozd létre a környezeti változót a `PHP_INI_` előtaggal. A script induláskor ez alapján írja a konfigurációt.
*Kivétel: Ha egy direktíva nevében **pont** (`.`) van, helyettesítsd azt **dupla aláhúzással** (`__`), mivel a formális OS validáció nem szereti a pontokat a bash környezeti változónevekben.*

**Példák az env listában:**
- `PHP_INI_display_errors=Off` -> Bekerülő kód a fájlba: `display_errors = Off`
- `PHP_INI_session__gc_maxlifetime=1440` -> Bekerülő kód: `session.gc_maxlifetime = 1440`

### 4. A PgBouncer paraméterezése
A PgBouncer (mivel ez elkapja a Moodle kéréseit és tartja a szálat a Postgres felé), az alábbiak szerint állítható:
- `PGBOUNCER_POOL_MODE=transaction`
- `PGBOUNCER_MAX_CLIENT_CONN=100`

> Fontos! A PgBouncer image-ben kényszerítettem, hogy a `5432`-es porton várja a bejövő (moodle) hálózati kapcsolatokat. Ezáltal transzparens a működés a Moodle app számára.

## Minta a Moodle `config.php`-hoz
Miután a konténerek elindultak és elvégezted a telepítést, a rendszernek ekképpen kell látnia a szolgáltatásaid az esetlegesen kézzel csatolt (volume) `config.php`-n keresztül:

```php
// --- Adatbázis ---
// A moodle a köztes PgBouncer-hez kapcsolódik!
$CFG->dbtype    = 'pgsql';
$CFG->dblibrary = 'native';
$CFG->dbhost    = 'moodle_pgbouncer';
$CFG->dbname    = 'moodle';
$CFG->dbuser    = 'moodle';
$CFG->dbpass    = 'moodle_password';
$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbport' => '5432', // Bár a PgBouncer natív portja sokszor 6432, mi a docker-compose.yml-ben 5432-re bindoltuk.
    'dbsocket' => '',
);

// --- Gyorsítótár / Redis ---
// Opcionálisan, a session kezelést kivezethetjük a Redis-be:
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host = 'moodle_redis';
$CFG->session_redis_port = 6379;
```

## 5. Ütemezett Feladatok (Cron / CLI) és Kubernetes Tervezés

A Moodle tökéletes működéséhez elengedhetetlen a háttérfolyamatok (Moodle Cron és Adhoc taskok) futtatása. A Docker bevált gyakorlatai (és különösen a magas rendelkezésre állású Kubernetes környezetek) szerint a háttérfolyamatokat érdemes a fő webes kiszolgálótól (Apache) **különálló konténerbe (vagy pod-ba)** szervezni.

A `docker-compose.yml` fájlban példaként szerepel egy `moodle-cli` nevű szolgáltatás, ami ugyanabból a képfájlból (image) épül fel, azonban a webszerver helyett egy végtelenített ciklusban futtatja a Moodle beépített cron scriptjét, biztosítva az aszinkron feladatok villámgyors futását:
`php admin/cli/cron.php --keep-alive=300`

**Példa Kubernetes (K8s) tervezéshez:**
Éles Kubernetes környezetben az architektúrát így érdemes kialakítani a példa alapján:
1. **Moodle Web Server:** Egy standard `Deployment` az image-ből, amit nyugodtan horizontálisan skálázhatsz (pl. HPA segítségével akár 10 replikáig) az aktuális CPU/Memory load alapján.
2. **Moodle CLI Worker:** Rendszerint _egy darab_ dedikált, kisebb erőforrásokkal rendelkező (pl. alacsonyabb CPU limit) `Deployment` replikaként vagy specifikus Moodle Worker-ként fut, amely kizárólag a Cron folyamatot tartja életben. Így garantáltan nem futnak egymással összeütköző cron jobok, és a háttérfolyamatok terhelése nem okoz lassulást a diákok számára a webes felületen. Vagy használhatsz natív K8s `CronJob`-ot perces ütemezéssel.

## 6. Horizontális skálázás Kubernetes (K8s) környezetben

Ahhoz, hogy a webes kiszolgálót (app server) felhős infrastruktúrán dinamikusan, terhelés alapján (HPA - Horizontal Pod Autoscaler) lehessen skálázni több replikára (például vizsgaidőszakban 10-20+ podra), az alábbi kulcsfontosságú architekturális elveket *kell* betartani a fürt kialakításakor:

1. **Osztott Fájlrendszer (Shared Storage - RWX):**
   A Moodle-nek *kötelezően* szüksége van egy közös `moodledata` állománytérre, amit minden újonnan felpörgő app pod egyidejűleg elér. Ezt a tárolót Kubernetes-ben `ReadWriteMany` (RWX) hozzáférési móddal kell beállítani és felcsatolni (Ilyen technológia pl. az AWS EFS, az Azure Files, vagy egy on-prem NFS szerver). Az alkalmazás konkrét kódjának viszont célszerű továbbra is a konténerbe sütve maradnia az optimális PHP betöltési (opcache) sebesség miatt.

2. **Redis az Ülésekhez (Sessions) és a Gyorsítótárhoz (MUC):**
   Amikor 5 podod fut, és a felhasználó kéréseit egy Load Balancer (Ingress) osztja el közöttük, a helyi pod lemezen futó sessions kikényszerítetten kijelentkezést fog okozni a következő navigáláskor. **Kötelező** a `config.php`-ban egy fürtözhető vagy egy dedikált központi Redis kiszolgálót beállítani "Session handler"-ként és alkalmazás szintű cache (MUC) céljára. *(Ezt a projektben lévő redis service már modellezi is számodra)*.

3. **PgBouncer és Adatbázis Kapcsolatok (Connection Pool Limitek):**
   Képzeld el, hogy a HPA felhúz 10 Moodle pod-ot. Ha minden pod-ban 50 a `PHP_FPM_MAX_CHILDREN`, az hirtelen csúcsidőben `10 * 50 = 500` nyitott tranzakciót és adatbázis TCP kapcsolatot jelenthet. A sima PostgreSQL kapcsolatkezelése ilyen terheléstől azonnal összeroppan. 
   Ezért került ebbe a dizájnba a **PgBouncer**! A horizontális skálázódáskor a PgBouncer-nek szánt `PGBOUNCER_MAX_CLIENT_CONN` értékét megemelheted akár több ezerre is (ennyi kérést fogad be szimultán a webről), a `PGBOUNCER_DEFAULT_POOL_SIZE` értékét pedig a tényleges PostgreSQL szervered teljesítményéhez lőheted be (például 100-as értékre). Így a Moodle biztonságosan, akadás (és Database Exceptionök) nélkül tud skálázódni a háttérben.

4. **Stateless Web App (Állapotmentesség):**
   Törekedj arra, hogy a webre mutató Moodle konténereid önmagukban teljesen állapotmentesek legyenek. Minden naplózott tartalom vagy naplófájl a stdout/stderr-re (Docker/K8s beépített logolására) menjen. Ebben az elkészített környezetben a PHP-FPM `catch_workers_output` configunk gondoskodik a hibák transzparens K8s konzolra küldéséről, így hiba esetén semmit nem nyel el a helyi virtuális lemez.

### Példa: Kubernetes Deployment (Web & CLI)

A lenti YAML fájlok bemutatják, hogyan fordíthatjuk le a `docker-compose.yml`-t valódi K8s specifikációra (Deployment), fizikailag is szétválasztva a terhelést.

```yaml
# 0. ConfigMap a Moodle konfiguráció (config.php) számára
apiVersion: v1
kind: ConfigMap
metadata:
  name: moodle-config
data:
  config.php: |
    <?php
    unset($CFG);
    global $CFG;
    $CFG = new stdClass();
    $CFG->dbtype    = 'pgsql';
    $CFG->dblibrary = 'native';
    $CFG->dbhost    = 'moodle-pgbouncer-service'; # A PgBouncer K8s Service neve
    $CFG->dbname    = 'moodle';
    $CFG->dbuser    = 'moodle';
    $CFG->dbpass    = 'moodle_password';
    $CFG->prefix    = 'mdl_';
    $CFG->dboptions = array(
        'dbpersist' => 0,
        'dbport' => '5432',
        'dbsocket' => '',
    );
    $CFG->wwwroot   = 'https://moodle.sajat-domained.com';
    $CFG->dataroot  = '/var/www/moodledata';
    $CFG->admin     = 'admin';
    # Redis Session
    $CFG->session_handler_class = '\core\session\redis';
    $CFG->session_redis_host = 'moodle-redis-service'; # A Redis K8s Service neve
    require_once(__DIR__ . '/lib/setup.php');

---
# 1. A horizontálisan skálázható (HPA) Web Server Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: moodle-web
spec:
  replicas: 3 # Ideális esetben HPA vezérli 3-20 között
  selector:
    matchLabels:
      app: moodle
      component: web
  template:
    metadata:
      labels:
        app: moodle
        component: web
    spec:
      containers:
      - name: moodle-web
        image: cnwzrt/pocmoodle:latest
        ports:
        - containerPort: 80
        env:
        - name: PHP_MEMORY_LIMIT
          value: "512M"
        - name: PHP_FPM_MAX_CHILDREN
          value: "50"
        - name: APACHE_MAX_REQUEST_WORKERS
          value: "150"
        volumeMounts:
        - name: moodledata-storage
          mountPath: /var/www/moodledata
        - name: config-volume
          mountPath: /var/www/html/config.php
          subPath: config.php
      volumes:
      - name: moodledata-storage
        persistentVolumeClaim:
          claimName: moodle-rwx-pvc # Amazon EFS / Azure Files alapú (ReadWriteMany) claim
      - name: config-volume
        configMap:
          name: moodle-config

---
# 2. A Moodle CLI Worker - Kizárólag a Cron scriptekért felel
apiVersion: apps/v1
kind: Deployment
metadata:
  name: moodle-cli
spec:
  replicas: 1 # KÖTELEZŐ: Szigorúan 1 replika a duplikált cron futások elkerülése miatt!
  selector:
    matchLabels:
      app: moodle
      component: cli
  template:
    metadata:
      labels:
        app: moodle
        component: cli
    spec:
      containers:
      - name: moodle-cron
        image: cnwzrt/pocmoodle:latest
        command:
          - sh
          - "-c"
          - |
            while true; do
              php admin/cli/cron.php --keep-alive=300
              sleep 60
            done
        env:
        - name: PHP_MEMORY_LIMIT
          value: "1024M" # A CLI script gyakran több memóriát igényel, mint egy átlagos webszál
        volumeMounts:
        - name: moodledata-storage
          mountPath: /var/www/moodledata
        - name: config-volume
          mountPath: /var/www/html/config.php
          subPath: config.php
      volumes:
      - name: moodledata-storage
        persistentVolumeClaim:
          claimName: moodle-rwx-pvc
      - name: config-volume
        configMap:
          name: moodle-config

---
# 3. PgBouncer Deployment és Service
apiVersion: apps/v1
kind: Deployment
metadata:
  name: moodle-pgbouncer
spec:
  replicas: 1 # PgBouncer önmagában ezer-tízezer kapcsolatot bír, általában elég 1-2 replika
  selector:
    matchLabels:
      app: moodle
      component: pgbouncer
  template:
    metadata:
      labels:
        app: moodle
        component: pgbouncer
    spec:
      containers:
      - name: pgbouncer
        image: bitnami/pgbouncer:latest
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRESQL_HOST
          value: "a-valodi-k8s-postgres-szolgaltatasod" # Erre a backendre fog proxy-zni!
        - name: PGBOUNCER_PORT
          value: "5432"
        - name: PGBOUNCER_DATABASE
          value: "moodle"
        - name: POSTGRESQL_USERNAME
          value: "moodle"
        - name: POSTGRESQL_PASSWORD
          value: "moodle_password"
        - name: PGBOUNCER_POOL_MODE
          value: "transaction"
        - name: PGBOUNCER_MAX_CLIENT_CONN
          value: "2000"
        - name: PGBOUNCER_DEFAULT_POOL_SIZE
          value: "100"
        - name: PGBOUNCER_AUTH_TYPE
          value: "scram-sha-256"
---
apiVersion: v1
kind: Service
metadata:
  name: moodle-pgbouncer-service
spec:
  selector:
    app: moodle
    component: pgbouncer
  ports:
    - protocol: TCP
      port: 5432
      targetPort: 5432

---
# 4. Horizontal Pod Autoscaler (HPA) a webes kiszolgálóhoz
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: moodle-web-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: moodle-web
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 75 # Ha az átlagos CPU meghaladja a 75%-ot, felhúz egy újabb Moodle podot.
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80 # Ha a memória töltődik túl, arra is reagál.
```
