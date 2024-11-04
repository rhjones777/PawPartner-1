import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelter_partner/models/volunteer.dart';
import 'package:shelter_partner/view_models/volunteers_view_model.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

// Providers
final usersWithEmailProvider = StateProvider<List<Map<String, dynamic>>>((ref) => []);
final usersToAddProvider = StateProvider<List<Map<String, dynamic>>>((ref) => []);
final usersToRemoveProvider = StateProvider<List<Volunteer>>((ref) => []);

class BetterImpactPage extends ConsumerStatefulWidget {
  const BetterImpactPage({Key? key}) : super(key: key);

  @override
  _BetterImpactPageState createState() => _BetterImpactPageState();
}

class _BetterImpactPageState extends ConsumerState<BetterImpactPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false; // Local loading state

  @override
  Widget build(BuildContext context) {
    Future<void> sync() async {
      final String username = usernameController.text;
      final String password = passwordController.text;

      final String basicAuth =
          'Basic ${base64Encode(utf8.encode('$username:$password'))}';

      final response = await http.get(
        Uri.parse('https://api.betterimpact.com/v1/organization/users/'),
        headers: <String, String>{'authorization': basicAuth},
      );

      if (response.statusCode == 200) {
        final List<dynamic> users = json.decode(response.body)['users'];

        final usersWithEmail = users
            .where((user) =>
                user['email_address'] != null && user['email_address'].isNotEmpty)
            .map((user) => {
                  'first_name': user['first_name'],
                  'last_name': user['last_name'],
                  'email_address': user['email_address']
                })
            .toList();

        ref.read(usersWithEmailProvider.notifier).state = usersWithEmail;

        // Access volunteerSettings safely
        final volunteerSettings = ref.read(volunteersViewModelProvider);
        if (volunteerSettings.value == null) {
          // Handle the case where volunteerSettings is not yet loaded
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Volunteer settings not loaded yet. Please try again.')),
          );
          return;
        }

        final shelterID = volunteerSettings.value!.id;

        // Get emails from API response and existing volunteers
        final Set<String> apiEmails = usersWithEmail
            .map((user) => user['email_address'] as String)
            .toSet();

        final Set<String> volunteerEmails = volunteerSettings.value!.volunteers
            .map((volunteer) => volunteer.email)
            .toSet();

        // Determine emails to add and remove
        final Set<String> emailsToAdd = apiEmails.difference(volunteerEmails);
        final Set<String> emailsToRemove = volunteerEmails.difference(apiEmails);

        // Get users to add
        final List<Map<String, dynamic>> usersToAdd = usersWithEmail
            .where((user) => emailsToAdd.contains(user['email_address']))
            .toList();

        final List<Volunteer> usersToRemove = volunteerSettings
            .value!.volunteers
            .where((volunteer) => emailsToRemove.contains(volunteer.email))
            .toList();

        // Update state providers
        ref.read(usersToAddProvider.notifier).state = usersToAdd;
        ref.read(usersToRemoveProvider.notifier).state = usersToRemove;

        // Show the dialog and wait for the result
        final shouldSync = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return SyncDialog(shelterID: shelterID);
          },
        );

        if (shouldSync == true) {
          setState(() {
            isLoading = true; // Show loading indicator
          });

          try {
            // Convert usersToAdd to List<Volunteer>
            final volunteersToAdd = usersToAdd.map((user) {
              return Volunteer(
                id: '', // Assign an appropriate ID if necessary
                firstName: user['first_name'],
                lastName: user['last_name'],
                email: user['email_address'],
              );
            }).toList();

            // Add new volunteers
            for (var volunteer in volunteersToAdd) {
              await ref
                  .read(volunteersViewModelProvider.notifier)
                  .sendVolunteerInvite(volunteer.firstName, volunteer.lastName,
                      volunteer.email, shelterID);
            }

            // Remove volunteers
            for (var volunteer in usersToRemove) {
              try {
                await ref
                    .read(volunteersViewModelProvider.notifier)
                    .deleteVolunteer(volunteer.id, shelterID);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to delete volunteer: $e')),
                );
              }
            }

            // Refresh the volunteer settings
            ref
                .read(volunteersViewModelProvider.notifier)
                .fetchShelterDetails(shelterID: shelterID);

            // Show success toast
            Fluttertoast.showToast(
              msg:
                  "${usersToAdd.length} volunteers added, ${usersToRemove.length} volunteers removed",
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.TOP,
              timeInSecForIosWeb: 1,
              backgroundColor: Colors.green,
              textColor: Colors.white,
              fontSize: 16.0,
            );

            // Navigate back to /volunteers
            context.go('/volunteers');
          } catch (e) {
            // Handle any errors
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error during sync: $e')),
            );
          } finally {
            setState(() {
              isLoading = false; // Hide loading indicator
            });
          }
        }
      } else {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('Error'),
              content: const Text('Failed to sync users.'),
              actions: <Widget>[
                TextButton(
                  child: const Text('OK'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Better Impact Sync'),
      ),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: isLoading, // Prevent interaction when loading
            child: Opacity(
              opacity: isLoading ? 0.5 : 1.0, // Fade background when loading
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        "Important: Please Read",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                          "This will add new users who are volunteers in Better Impact and whose status is \"Accepted\" and remove users who are no longer in Better Impact or whose status is no longer \"Accepted\"."),
                      const SizedBox(height: 20),
                      const Text(
                          "Because of privacy laws, volunteers will not stay up to date automatically. You will have to come back here whenever you want to resync the volunteers. The username and password are NOT your normal login. They are generated by following the link below. Make sure to only select the \"Volunteer\" checkbox when creating the key. The username and password will not be saved anywhere and will only be used to sync your volunteers."),
                      const SizedBox(height: 20),
                      InkWell(
                        onTap: () async {
                          const url =
                              'https://support.betterimpact.com/volunteerimpacthelp/en/help-articles/it/';
                          if (await canLaunch(url)) {
                            await launch(url);
                          } else {
                            throw 'Could not launch $url';
                          }
                        },
                        child: const Text(
                          'How To Generate Username and Password (API Key)',
                          style: TextStyle(
                            color: Colors.blue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: usernameController,
                        decoration: const InputDecoration(labelText: 'Username'),
                      ),
                      TextField(
                        controller: passwordController,
                        decoration: const InputDecoration(labelText: 'Password'),
                        obscureText: true,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: isLoading ? null : sync,
                        child: const Text('Sync'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isLoading)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading...'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class SyncDialog extends ConsumerWidget {
  final String shelterID;
  const SyncDialog({Key? key, required this.shelterID}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersToAdd = ref.watch(usersToAddProvider);
    final usersToRemove = ref.watch(usersToRemoveProvider);

    return AlertDialog(
      title: const Text('Users to Sync'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (usersToAdd.isNotEmpty) ...[
                const Text('Add:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: usersToAdd.length,
                  itemBuilder: (context, index) {
                    final user = usersToAdd[index];
                    return ListTile(
                      title: Text(
                          '${user['first_name']} ${user['last_name']}: ${user['email_address']}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          ref.read(usersToAddProvider.notifier).state =
                              usersToAdd.where((u) => u != user).toList();
                        },
                      ),
                    );
                  },
                ),
              ],
              if (usersToRemove.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Remove:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: usersToRemove.length,
                  itemBuilder: (context, index) {
                    final volunteer = usersToRemove[index];
                    return ListTile(
                      title: Text(
                          '${volunteer.firstName} ${volunteer.lastName}: ${volunteer.email}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          ref.read(usersToRemoveProvider.notifier).state =
                              usersToRemove
                                  .where((v) => v != volunteer)
                                  .toList();
                        },
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () {
            Navigator.of(context).pop(false);
          },
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(true); // Dismiss and proceed with sync
          },
          child: const Text('Sync'),
        ),
      ],
    );
  }
}
