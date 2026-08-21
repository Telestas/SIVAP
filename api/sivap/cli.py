"""Órdenes de administración.

    python -m sivap.cli crear-investigador --usuario x --nombre "Dra. X" \
        --institucion HC --rol reclutador --rol aplicador

La primera cuenta hay que crearla desde el servidor: no existe registro abierto,
y en un ensayo donde los permisos sostienen el cegamiento eso no es una carencia.
"""

import argparse
import getpass
import sys
import uuid

from . import bd
from .seguridad import cifrar_credencial

ROLES = ('reclutador', 'aplicador', 'evaluador_desenlaces', 'analista',
         'investigador_principal', 'observador')


def crear_investigador(args) -> int:
    if not set(args.rol) <= set(ROLES):
        print(f'Roles válidos: {", ".join(ROLES)}', file=sys.stderr)
        return 2

    contrasena = args.contrasena or getpass.getpass('Contraseña: ')
    if len(contrasena) < 8:
        print('La contraseña debe tener al menos 8 caracteres.', file=sys.stderr)
        return 2

    nuevo = uuid.uuid4()
    with bd.conexion() as con:
        if bd.uno(con, 'SELECT 1 FROM institucion WHERE codigo = %s',
                  (args.institucion,)) is None:
            print(f'No existe el centro «{args.institucion}».', file=sys.stderr)
            return 2

        bd.ejecutar(
            con,
            'INSERT INTO investigador (id, usuario, nombre, credencial_hash,'
            ' institucion_codigo) VALUES (%s, %s, %s, %s, %s)',
            (nuevo, args.usuario, args.nombre, cifrar_credencial(contrasena),
             args.institucion),
        )
        for rol in args.rol:
            bd.ejecutar(
                con,
                'INSERT INTO investigador_rol (investigador_id, rol)'
                ' VALUES (%s, %s)', (nuevo, rol))

        # Avisar, no impedir: si un centro pequeño necesita que una persona
        # aplique y evalúe, esa es una decisión de la investigadora principal.
        # Lo que no puede es pasar desapercibida.
        if {'aplicador', 'evaluador_desenlaces'} <= set(args.rol):
            print('AVISO: esta persona aplica el protocolo y evalúa desenlaces.'
                  ' Esa combinación rompe el cegamiento del desenlace principal.',
                  file=sys.stderr)

    print(f'Investigador creado: {args.usuario} ({nuevo})')
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog='sivap.cli')
    sub = p.add_subparsers(dest='orden', required=True)

    c = sub.add_parser('crear-investigador')
    c.add_argument('--usuario', required=True)
    c.add_argument('--nombre', required=True)
    c.add_argument('--institucion', required=True)
    c.add_argument('--rol', action='append', required=True, choices=ROLES)
    c.add_argument('--contrasena', help='si se omite, se pide por teclado')
    c.set_defaults(func=crear_investigador)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == '__main__':
    raise SystemExit(main())
