# -*- coding: utf-8 -*-
from urllib import parse

from config import RUN_VER, MFA_TIME_OUT

if RUN_VER == 'open':
    from blueapps.patch.settings_open_saas import *  # noqa
else:
    from blueapps.patch.settings_paas_services import *  # noqa

# 正式环境
RUN_MODE = 'PRODUCT'

# 只对正式环境日志级别进行配置，可以在这里修改
LOG_LEVEL = 'ERROR'

# V2
# import logging
# logging.getLogger('root').setLevel('INFO')
# V3
# import logging
# logging.getLogger('app').setLevel('INFO')

GUACD_HOST = '127.0.0.1'
GUACD_PORT = '4822'
# 对应guacd的路径如下
GUACD_PATH = "/srv/guacamole"

MEDIA_URL = ''
UPLOAD_PATH = os.getenv("UPLOAD_PATH", "/opt/opsany/")
TERMINAL_PATH = os.path.join(os.getenv("UPLOAD_PATH", "/opt/opsany/"), "uploads/terminal")
ORI_GUACD_PATH = os.path.join(os.getenv("UPLOAD_PATH", "/opt/opsany/"), "uploads/guacamole")
TERMINAL_TIMEOUT = int(os.getenv("TERMINAL_TIMEOUT", 1800))

DATABASES.update(
    {
        'default': {
            'ENGINE': 'django.db.backends.mysql',
            'NAME': 'bastion',  # 数据库名
            'USER': 'bastion',  # 数据库用户
            'PASSWORD': os.getenv("MYSQL_PASSWORD", APP_CODE),  # 数据库密码
            'HOST': os.getenv("MYSQL_HOST", "127.0.0.1"),  # 数据库主机
            'PORT': int(os.getenv("MYSQL_PORT", "3306")),  # 数据库端口
            'OPTIONS': {
                "init_command": "SET default_storage_engine=INNODB",
            }

        },
    }
)

REDIS_HOST = os.getenv("REDIS_HOST", "127.0.0.1")
REDIS_PORT = os.getenv("REDIS_PORT", "6379")
REDIS_USERNAME = parse.quote(os.getenv("REDIS_USERNAME", "") or "")
REDIS_PASSWORD = parse.quote(os.getenv("REDIS_PASSWORD", APP_CODE))  # 密码URL编译，防止出现@等符号

CACHES.update(
    {
        "default": {
            "BACKEND": "django_redis.cache.RedisCache",
            "LOCATION": "redis://{}:{}@{}:{}/1".format(REDIS_USERNAME, REDIS_PASSWORD, REDIS_HOST, REDIS_PORT),
            'TIMEOUT': 86400,
            "OPTIONS": {
                "CLIENT_CLASS": "django_redis.client.DefaultClient",
                "CONNECTION_POOL_KWARGS": {"max_connections": 1000},
            }
        },
        "cache": {
            "BACKEND": "django_redis.cache.RedisCache",
            "LOCATION": "redis://{}:{}@{}:{}/9".format(REDIS_USERNAME, REDIS_PASSWORD, REDIS_HOST, REDIS_PORT),
            'TIMEOUT': 1800,
            "OPTIONS": {
                "CLIENT_CLASS": "django_redis.client.DefaultClient",
                "CONNECTION_POOL_KWARGS": {"max_connections": 1000},
                # "PASSWORD": REDIS_PASSWORD,
            }
        },
        "mfa": {
            "BACKEND": "django_redis.cache.RedisCache",
            "LOCATION": "redis://{}:{}@{}:{}/8".format(REDIS_USERNAME, REDIS_PASSWORD, REDIS_HOST, REDIS_PORT),
            'TIMEOUT': 1800,
            "OPTIONS": {
                "CLIENT_CLASS": "django_redis.client.DefaultClient",
                "CONNECTION_POOL_KWARGS": {"max_connections": 1000},
                # "PASSWORD": REDIS_PASSWORD,
            }
        },
        "pod_login": {
            "BACKEND": "django_redis.cache.RedisCache",
            "LOCATION": "redis://{}:{}@{}:{}/14".format(REDIS_USERNAME, REDIS_PASSWORD, REDIS_HOST, REDIS_PORT),
            'TIMEOUT': 1800,
            "OPTIONS": {
                "CLIENT_CLASS": "django_redis.client.DefaultClient",
                "CONNECTION_POOL_KWARGS": {"max_connections": 1000},
                # "PASSWORD": REDIS_PASSWORD,
            }
        }
    }
)


CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels_redis.core.RedisChannelLayer',
        'CONFIG': {
            'hosts': ["redis://{}:{}@{}:{}/8".format(REDIS_USERNAME, REDIS_PASSWORD, REDIS_HOST, REDIS_PORT)],
            "symmetric_encryption_keys": [SECRET_KEY],
        },
    }
}
