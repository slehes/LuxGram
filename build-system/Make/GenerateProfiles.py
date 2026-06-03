import json
import os
import sys
import shutil
import tempfile
import plistlib
import argparse
import subprocess
import base64

from BuildEnvironment import run_executable_with_output, check_run_system


def setup_temp_keychain(p12_path, p12_password=''):
    """Create a temporary keychain and import the p12 certificate."""
    keychain_name = 'generate-profiles-temp.keychain'
    keychain_password = 'temp123'

    # Delete if exists
    run_executable_with_output('security', arguments=['delete-keychain', keychain_name], check_result=False)

    # Create keychain
    run_executable_with_output('security', arguments=[
        'create-keychain', '-p', keychain_password, keychain_name
    ], check_result=True)

    # Add to search list
    existing = run_executable_with_output('security', arguments=['list-keychains', '-d', 'user'])
    run_executable_with_output('security', arguments=[
        'list-keychains', '-d', 'user', '-s', keychain_name, existing.replace('"', '')
    ], check_result=True)

    # Unlock and set settings
    run_executable_with_output('security', arguments=['set-keychain-settings', keychain_name])
    run_executable_with_output('security', arguments=[
        'unlock-keychain', '-p', keychain_password, keychain_name
    ])

    # Import p12
    run_executable_with_output('security', arguments=[
        'import', p12_path, '-k', keychain_name, '-P', p12_password,
        '-T', '/usr/bin/codesign', '-T', '/usr/bin/security'
    ], check_result=True)

    # Set partition list for access
    run_executable_with_output('security', arguments=[
        'set-key-partition-list', '-S', 'apple-tool:,apple:', '-k', keychain_password, keychain_name
    ], check_result=True)

    return keychain_name


def cleanup_temp_keychain(keychain_name):
    """Remove the temporary keychain."""
    run_executable_with_output('security', arguments=['delete-keychain', keychain_name], check_result=False)


def get_signing_identity_from_p12(p12_path, p12_password=''):
    """Extract the common name (signing identity) from the p12 certificate."""
    # Try with -legacy first
    proc = subprocess.Popen(
        ['openssl', 'pkcs12', '-in', p12_path, '-passin', 'pass:' + p12_password, '-nokeys', '-legacy'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    cert_pem, _ = proc.communicate()

    # If legacy fails, try without -legacy
    if not cert_pem or b'error' in cert_pem.lower():
        proc = subprocess.Popen(
            ['openssl', 'pkcs12', '-in', p12_path, '-passin', 'pass:' + p12_password, '-nokeys'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        cert_pem, _ = proc.communicate()

    if not cert_pem:
        return None

    proc2 = subprocess.Popen(
        ['openssl', 'x509', '-noout', '-subject', '-nameopt', 'oneline,-esc_msb'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    subject, _ = proc2.communicate(cert_pem)
    subject = subject.decode('utf-8').strip()

    # Parse CN from subject line like: subject= C = AE, O = ..., CN = Some Name
    if 'CN = ' in subject:
        cn = subject.split('CN = ')[-1].split(',')[0].strip()
        return cn
    # Also try format: subject=/CN=...
    elif '/CN=' in subject:
        cn = subject.split('/CN=')[-1].split('/')[0].strip()
        return cn

    return None


def get_certificate_base64_from_p12(p12_path, p12_password=''):
    """Extract the certificate as base64 from p12 file."""
    # Extract certificate in PEM format - try without -legacy first (newer openssl doesn't support it)
    proc = subprocess.Popen(
        ['openssl', 'pkcs12', '-in', p12_path, '-passin', 'pass:' + p12_password, '-nokeys'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    cert_pem, stderr = proc.communicate()

    # If that fails, try with -legacy (older openssl)
    if not cert_pem or b'error' in stderr.lower() or b'unable' in stderr.lower() or b'MAC' not in stderr:
        proc = subprocess.Popen(
            ['openssl', 'pkcs12', '-in', p12_path, '-passin', 'pass:' + p12_password, '-nokeys', '-legacy'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        cert_pem, _ = proc.communicate()

    if not cert_pem or b'CERTIFICATE' not in cert_pem:
        return None

    # Convert to DER format
    proc2 = subprocess.Popen(
        ['openssl', 'x509', '-outform', 'DER'],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    cert_der, _ = proc2.communicate(cert_pem)

    if not cert_der:
        return None

    return base64.b64encode(cert_der).decode('utf-8')


def _remap_plist_value(value, replacements):
    """Recursively replace strings in a plist value according to an ordered replacement list."""
    if isinstance(value, str):
        for old, new in replacements:
            value = value.replace(old, new)
        return value
    elif isinstance(value, list):
        return [_remap_plist_value(v, replacements) for v in value]
    elif isinstance(value, dict):
        return {k: _remap_plist_value(v, replacements) for k, v in value.items()}
    return value


def process_provisioning_profile(source, destination, certificate_data, signing_identity, keychain_name,
                                  source_team_id=None, target_team_id=None,
                                  source_bundle_id=None, target_bundle_id=None):
    import plistlib

    # Parse the provisioning profile using security cms -D to get XML plist
    parsed_plist_xml = run_executable_with_output('security', arguments=['cms', '-D', '-i', source], check_result=True)
    parsed_plist_file = tempfile.mktemp()
    with open(parsed_plist_file, 'w+') as file:
        file.write(parsed_plist_xml)

    # Convert XML plist to binary plist for manipulation
    binary_plist_file = tempfile.mktemp()
    run_executable_with_output('plutil', arguments=['-convert', 'binary1', '-o', binary_plist_file, parsed_plist_file], check_result=True)

    # Load binary plist using plistlib
    with open(binary_plist_file, 'rb') as f:
        plist_data = plistlib.load(f)

    # Remap team ID and bundle ID if requested (order matters: longest matches first)
    if source_team_id and target_team_id and source_bundle_id and target_bundle_id:
        replacements = [
            (source_team_id + '.' + source_bundle_id, target_team_id + '.' + target_bundle_id),
            ('group.' + source_bundle_id,              'group.' + target_bundle_id),
            (source_bundle_id,                         target_bundle_id),
            (source_team_id,                           target_team_id),
        ]
        plist_data = _remap_plist_value(plist_data, replacements)

    # Decode certificate from base64
    cert_der = base64.b64decode(certificate_data)

    # Replace DeveloperCertificates array with new certificate
    plist_data['DeveloperCertificates'] = [cert_der]

    # Remove DER-Encoded-Profile if present
    if 'DER-Encoded-Profile' in plist_data:
        del plist_data['DER-Encoded-Profile']

    # Write updated binary plist
    with open(binary_plist_file, 'wb') as f:
        plistlib.dump(plist_data, f)

    # Convert back to XML for signing
    run_executable_with_output('plutil', arguments=['-convert', 'xml1', '-o', parsed_plist_file, binary_plist_file], check_result=True)

    # Sign with the certificate from the temporary keychain
    run_executable_with_output('security', arguments=[
        'cms', '-S', '-k', keychain_name, '-N', signing_identity, '-i', parsed_plist_file, '-o', destination
    ], check_result=True)

    os.unlink(parsed_plist_file)
    os.unlink(binary_plist_file)


def generate_provisioning_profiles(source_path, destination_path, certs_path,
                                    source_team_id=None, target_team_id=None,
                                    source_bundle_id=None, target_bundle_id=None):
    p12_path = os.path.join(certs_path, 'SelfSigned.p12')

    if not os.path.exists(p12_path):
        print('{} does not exist'.format(p12_path))
        sys.exit(1)

    if not os.path.exists(destination_path):
        print('{} does not exist'.format(destination_path))
        sys.exit(1)

    # Extract certificate info from p12
    p12_password = os.environ.get('P12_PASSWORD', '')
    certificate_data = get_certificate_base64_from_p12(p12_path, p12_password)
    signing_identity = get_signing_identity_from_p12(p12_path, p12_password)

    if not signing_identity:
        print('Could not extract signing identity from {}'.format(p12_path))
        sys.exit(1)

    print('Using signing identity: {}'.format(signing_identity))

    # Setup temporary keychain with the certificate
    keychain_name = setup_temp_keychain(p12_path, p12_password)

    try:
        for file_name in os.listdir(source_path):
            if file_name.endswith('.mobileprovision'):
                print('Processing {}'.format(file_name))
                process_provisioning_profile(
                    source=os.path.join(source_path, file_name),
                    destination=os.path.join(destination_path, file_name),
                    certificate_data=certificate_data,
                    signing_identity=signing_identity,
                    keychain_name=keychain_name,
                    source_team_id=source_team_id,
                    target_team_id=target_team_id,
                    source_bundle_id=source_bundle_id,
                    target_bundle_id=target_bundle_id,
                )
        print('Done. Generated {} profiles.'.format(
            len([f for f in os.listdir(destination_path) if f.endswith('.mobileprovision')])
        ))
    finally:
        cleanup_temp_keychain(keychain_name)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Regenerate fake provisioning profiles with updated bundle IDs')
    parser.add_argument('--sourcePath', required=True, help='Directory containing source .mobileprovision files')
    parser.add_argument('--destinationPath', required=True, help='Output directory for regenerated profiles')
    parser.add_argument('--certsPath', required=True, help='Directory containing SelfSigned.p12')
    parser.add_argument('--sourceTeamId', default='C67CF9S4VU', help='Team ID to replace')
    parser.add_argument('--targetTeamId', required=True, help='New team ID')
    parser.add_argument('--sourceBundleId', default='ph.telegra.Telegraph', help='Bundle ID to replace')
    parser.add_argument('--targetBundleId', required=True, help='New bundle ID')
    args = parser.parse_args()

    os.makedirs(args.destinationPath, exist_ok=True)
    generate_provisioning_profiles(
        source_path=args.sourcePath,
        destination_path=args.destinationPath,
        certs_path=args.certsPath,
        source_team_id=args.sourceTeamId,
        target_team_id=args.targetTeamId,
        source_bundle_id=args.sourceBundleId,
        target_bundle_id=args.targetBundleId,
    )
