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
