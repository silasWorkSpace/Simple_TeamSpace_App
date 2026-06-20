import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:last_project_client/controllers/auth_controller.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthController>().currentUser;

    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final initial = user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          // Avatar
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.blue.shade100,
            child: Text(
              initial,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Display Name
          Text(
            user.displayName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 32),

          // Details Card
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                // User ID (Prominent & Copy-Friendly)
                ListTile(
                  leading: const Icon(Icons.badge_outlined, color: Colors.blue),
                  title: const Text('User ID', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  subtitle: SelectableText(
                    '${user.id}',
                    style: const TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.bold, 
                      color: Colors.black87,
                    ),
                  ),
                ),
                const Divider(height: 1),
                
                // Phone Number
                ListTile(
                  leading: const Icon(Icons.phone_android_outlined, color: Colors.grey),
                  title: const Text('Phone Number', style: TextStyle(fontSize: 13, color: Colors.grey)),
                  subtitle: SelectableText(
                    user.phone,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 48),

          // Logout Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () {
                context.read<AuthController>().logout();
              },
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text(
                'Log Out',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
