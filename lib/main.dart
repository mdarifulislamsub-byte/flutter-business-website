import 'dart:typed_data';
import 'dart:async';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'web_helper_stub.dart' if (dart.library.html) 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'pdf_viewer_page.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:universal_html/html.dart' as web;
import 'package:flutter/gestures.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// --- Cloudinary Universal Upload Function ---
Future<String> uploadToCloudinary(
    Uint8List fileBytes,
    String fileName, {
      String folder = "portfolio",
    }) async {
  const String cloudName = "c9thhaqw";
  const String uploadPreset = "portfolio_unsigned";

  final uri = Uri.parse(
    "https://api.cloudinary.com/v1_1/$cloudName/auto/upload",
  );
  final request = http.MultipartRequest("POST", uri)
    ..fields['upload_preset'] = uploadPreset
    ..fields['folder'] = folder
    ..files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ),
    );

  try {
    final response = await request.send();
    if (response.statusCode == 200) {
      final resStr = await response.stream.bytesToString();
      final data = jsonDecode(resStr);
      return data['secure_url'] ?? "";
    } else {
      debugPrint("Cloudinary Upload Error: ${response.statusCode}");
      return "";
    }
  } catch (e) {
    debugPrint("Cloudinary Exception: $e");
    return "";
  }
}

void updateBrowserFavicon(String imageUrl) {
  if (!kIsWeb || imageUrl.isEmpty) return;
  final String separator = imageUrl.contains('?') ? '&' : '?';
  final String iconUrl =
      '$imageUrl${separator}v=${DateTime.now().millisecondsSinceEpoch}';
  final favicon = web.document.getElementById('appFavicon');
  if (favicon != null) {
    favicon.setAttribute('href', iconUrl);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("Firebase initialized successfully");
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
  }
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: const PortfolioScreen(),
  ));
}

class CertificateData {
  String name;
  Uint8List? bytes;
  String? imageUrl;
  CertificateData({required this.name, this.bytes, this.imageUrl});
}

class DesignationData {
  String title;
  String fromDate;
  String toDate;
  String serviceLength;

  DesignationData({
    this.title = '',
    this.fromDate = '',
    this.toDate = '',
    this.serviceLength = '',
  });
}

class ExperienceData {
  String companyName;
  String date;
  String designation;
  List<DesignationData> designations;
  String description;
  List<CertificateData> certificates;

  ExperienceData({
    this.companyName = '',
    this.date = '',
    this.designation = '',
    List<DesignationData>? designations,
    this.description = '',
    List<CertificateData>? certificates,
  })  : designations = designations ?? [],
        certificates = certificates ?? [];
}

class ExpertiseItemData {
  String title;
  Uint8List? iconBytes;
  String? iconUrl;
  List<String> bulletPoints;
  String levelOrPercentage;

  ExpertiseItemData({
    this.title = '',
    this.iconBytes,
    this.iconUrl,
    List<String>? bulletPoints,
    this.levelOrPercentage = '',
  }) : bulletPoints = bulletPoints ?? [];
}

class ExpertiseSectionData {
  String sectionTitle;
  List<ExpertiseItemData> items;

  ExpertiseSectionData({
    this.sectionTitle = '',
    List<ExpertiseItemData>? items,
  }) : items = items ?? [];
}

class ProjectData {
  String projectName;
  String title;
  String challengesAndSolutions;
  String keyFeatures;
  String githubUrl;
  String codeSnippet;

  // NEW Editable Text
  String stackDescription;

  // Images
  List<Uint8List> mediaFiles;
  List<String> mediaUrls;

  ProjectData({
    this.projectName = '',
    this.title = '',
    this.challengesAndSolutions = '',
    this.keyFeatures = '',
    this.githubUrl = '',
    this.codeSnippet = '',
    this.stackDescription = '',
    List<Uint8List>? mediaFiles,
    List<String>? mediaUrls,
  })  : mediaFiles = mediaFiles ?? [],
        mediaUrls = mediaUrls ?? [];
}

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}
class _PortfolioScreenState extends State<PortfolioScreen> {
  final InternetConnection _internetConnection = InternetConnection();
  final TransformationController _homeViewController =
  TransformationController();
  StreamSubscription<InternetStatus>? _internetSubscription;
  bool _hasInternet = true;
  bool _isCheckingInternet = true;
  String emailAddress = '';
  String phoneNumber = '';
  String linkedinUrl = '';
  List<Map<String, dynamic>> _experiences = [];
  @override
  void initState() {
    super.initState();
    _startInternetMonitoring();
  }
  Future<void> _startInternetMonitoring() async {
    bool connected = false;
    try {
      connected = await _internetConnection.hasInternetAccess;
    } catch (_) {
      connected = false;
    }
    if (!mounted) return;
    setState(() {
      _hasInternet = connected;
      _isCheckingInternet = false;
    });
    if (connected) {
      _fetchData();
      _loadDataFromFirestore();
    }
    _internetSubscription = _internetConnection.onStatusChange.listen(
          (InternetStatus status) {
        final bool isConnected =
            status == InternetStatus.connected;
        if (!mounted || isConnected == _hasInternet) return;
        setState(() {
          _hasInternet = isConnected;
          _isCheckingInternet = false;
        });

        if (isConnected) {
          _fetchData();
          _loadDataFromFirestore();
        }
      },
    );
  }

  @override
  void dispose() {
    _internetSubscription?.cancel();
    _homeViewController.dispose();
    super.dispose();
  }
  Future<void> _updateFirestoreData() async {
    try {
      await FirebaseFirestore.instance
          .collection('my_portfolio')
          .doc('user_data')
          .update({
        'emailAddress': emailAddress,
        'phoneNumber': phoneNumber,
        'linkedinUrl': linkedinUrl,
      });
      debugPrint("Firestore Update Successfully!");
    } catch (e) {
      debugPrint("Anything Worng can't Update: $e");
    }
  }
  Future<void> _updateField(String key, String value) async {
    await FirebaseFirestore.instance
        .collection('my_portfolio')
        .doc('user_data')
        .update({key: value});
    debugPrint("$key Update Successfully!");
  }
  void _fetchData() async {
    try {
      DocumentSnapshot snapshot = await FirebaseFirestore.instance
          .collection('my_portfolio')
          .doc('user_data')
          .get();

      if (snapshot.exists) {
        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

        debugPrint("Full Document Data: $data");

        setState(() {
          emailAddress = data['emailAddress']?.toString() ?? 'No Email';
          phoneNumber = data['phoneNumber']?.toString() ?? 'No Phone';
          linkedinUrl = data['linkedinUrl']?.toString() ?? 'No LinkedIn';
        });
      } else {
        debugPrint("Document 'user_data' does not exist!");
      }
    } catch (e) {
      debugPrint("Error fetching data: $e");
    }
  }

  // --- Cloudinary Universal Upload Function ---
  Future<String> uploadToCloudinary(
      Uint8List fileBytes,
      String fileName, {
        String folder = "portfolio",
      }) async {
    const String cloudName = "c9thhaqw";
    const String uploadPreset = "portfolio_unsigned";

    final uri = Uri.parse(
      "https://api.cloudinary.com/v1_1/$cloudName/auto/upload",
    );
    final request = http.MultipartRequest("POST", uri)
      ..fields['upload_preset'] = uploadPreset
      ..fields['folder'] = folder
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ),
      );

    try {
      final response = await request.send();
      if (response.statusCode == 200) {
        final resStr = await response.stream.bytesToString();
        final data = jsonDecode(resStr);
        return data['secure_url'] ?? "";
      } else {
        debugPrint("Cloudinary Upload Error: ${response.statusCode}");
        return "";
      }
    } catch (e) {
      debugPrint("Cloudinary Exception: $e");
      return "";
    }
  }

  Future<String?> uploadResumeToStorage(
      Uint8List pdfBytes,
      String fileName,
      ) async {
    try {
      final url = await uploadToCloudinary(
        pdfBytes,
        fileName,
        folder: "portfolio/resumes",
      );
      return url.isNotEmpty ? url : null;
    } catch (e) {
      debugPrint("PDF Upload error: $e");
      return null;
    }
  }
  Future<void> _updateContactField(BuildContext context, String key, String value) async {
    try {
      Map<String, dynamic> dataToUpdate = {};
      dataToUpdate[key] = value;

      await FirebaseFirestore.instance
          .collection('my_portfolio')
          .doc('user_data')
          .set(dataToUpdate, SetOptions(merge: true));

      setState(() {
        if (key == 'emailAddress') emailAddress = value;
        if (key == 'phoneNumber') phoneNumber = value;
        if (key == 'linkedinUrl') linkedinUrl = value;
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$key Save Successfully!")),
        );
      }

      print("SUCCESS: $key updated to $value");
    } catch (e) {
      print("ERROR: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Something Worng Can't Save: $e")),
        );
      }
    }
  }
  Future<void> _savePersonalInfo() async {
    try {
      await FirebaseFirestore.instance
          .collection('my_portfolio')
          .doc('user_data')
          .set({
        'profileName': profileName,
        'colam4': colam4,
        'colam5': colam5,
        'colam6': colam6,
        'aboutMe': aboutMe,
        'operationalDomain': operationalDomain,
        'technicalStack': technicalStack,
        'aboutMeTitle': aboutMeTitle,
        'operationalDomainTitle': operationalDomainTitle,
        'technicalStackTitle': technicalStackTitle,
        'homeMenuTitle': homeMenuTitle,
        'resumeMenuTitle': resumeMenuTitle,
        'projectMenuTitle': projectMenuTitle,
        'experienceMenuTitle': experienceMenuTitle,
        'expertiseMenuTitle': expertiseMenuTitle,

        'emailAddress': emailAddress,
        'phoneNumber': phoneNumber,
        'linkedinUrl': linkedinUrl,
      }, SetOptions(merge: true));

      debugPrint("Personal information saved successfully.");
    } catch (e) {
      debugPrint("Error saving personal information: $e");
    }
  }

  void _showCertificateGalleryDialog(
      BuildContext context,
      List<CertificateData> certificates,
      int initialIndex,
      ) {
    int currentIndex = initialIndex;

    final PageController pageController = PageController(
      initialPage: initialIndex,
    );

    showDialog(
      context: context,
      builder: (context) {
        final screenSize = MediaQuery.of(context).size;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentCertificate = certificates[currentIndex];

            return Dialog(
              insetPadding: const EdgeInsets.all(20),
              child: SizedBox(
                width: screenSize.width * 0.90,
                height: screenSize.height * 0.85,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 8,
                        top: 8,
                        bottom: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              currentCertificate.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          Text(
                            '${currentIndex + 1}/${certificates.length}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 1),

                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PageView.builder(
                            controller: pageController,
                            itemCount: certificates.length,
                            onPageChanged: (index) {
                              setDialogState(() {
                                currentIndex = index;
                              });
                            },
                            itemBuilder: (context, index) {
                              final certificate = certificates[index];

                              return Padding(
                                padding: const EdgeInsets.all(12),
                                child: InteractiveViewer(
                                  minScale: 0.5,
                                  maxScale: 5.0,
                                  child: Center(
                                    child: certificate.bytes != null
                                        ? Image.memory(
                                      certificate.bytes!,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.contain,
                                    )
                                        : certificate.imageUrl != null &&
                                        certificate.imageUrl!.isNotEmpty
                                        ? Image.network(
                                      certificate.imageUrl!,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.contain,
                                      loadingBuilder: (
                                          context,
                                          child,
                                          loadingProgress,
                                          ) {
                                        if (loadingProgress == null) {
                                          return child;
                                        }

                                        return const Center(
                                          child:
                                          CircularProgressIndicator(),
                                        );
                                      },
                                      errorBuilder: (
                                          context,
                                          error,
                                          stackTrace,
                                          ) {
                                        return const Icon(
                                          Icons.broken_image,
                                          size: 60,
                                        );
                                      },
                                    )
                                        : const Icon(
                                      Icons.image_not_supported,
                                      size: 60,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          if (currentIndex > 0)
                            Positioned(
                              left: 10,
                              child: CircleAvatar(
                                backgroundColor: Colors.black54,
                                child: IconButton(
                                  onPressed: () {
                                    pageController.previousPage(
                                      duration:
                                      const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.arrow_back_ios_new,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),

                          if (currentIndex < certificates.length - 1)
                            Positioned(
                              right: 10,
                              child: CircleAvatar(
                                backgroundColor: Colors.black54,
                                child: IconButton(
                                  onPressed: () {
                                    pageController.nextPage(
                                      duration:
                                      const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      pageController.dispose();
    });
  }

  void _loadDataFromFirestore() async {
    try {
      var snapshot = await FirebaseFirestore.instance
          .collection('my_portfolio')
          .doc('user_data')
          .get();
      if (snapshot.exists) {
        var data = snapshot.data();
        final String savedFaviconUrl =
            data?['faviconUrl']?.toString() ?? '';

        if (savedFaviconUrl.isNotEmpty) {
          updateBrowserFavicon(savedFaviconUrl);
        }

        setState(() {
          var expData = data?['experiences'] ?? [];

          _experiences = List<Map<String, dynamic>>.from(expData);

          experiencesList = _experiences.map((e) {
            final String oldDesignation =
            (e['designation'] ?? '').toString();

            final List<dynamic> designationData =
                e['designations'] as List<dynamic>? ?? [];

            final List<DesignationData> loadedDesignations =
            designationData.map((item) {
              final Map<String, dynamic> designationMap =
              Map<String, dynamic>.from(item as Map);

              return DesignationData(
                title: designationMap['title']?.toString() ?? '',
                fromDate:
                designationMap['fromDate']?.toString() ?? '',
                toDate:
                designationMap['toDate']?.toString() ?? '',
                serviceLength:
                designationMap['serviceLength']?.toString() ?? '',
              );
            }).toList();

            // Old single designation transfer to new list
            if (loadedDesignations.isEmpty &&
                oldDesignation.trim().isNotEmpty) {
              loadedDesignations.add(
                DesignationData(
                  title: oldDesignation,
                  fromDate: '',
                  toDate: '',
                  serviceLength: '',
                ),
              );
            }

            final List<dynamic> certificateData =
                e['certificates'] as List<dynamic>? ?? [];

            return ExperienceData(
              companyName: e['companyName']?.toString() ?? '',
              date: e['date']?.toString() ?? '',
              designation: oldDesignation,
              designations: loadedDesignations,
              description: e['description']?.toString() ?? '',
              certificates: certificateData.map((item) {
                final Map<String, dynamic> certificateMap =
                Map<String, dynamic>.from(item as Map);

                return CertificateData(
                  name: certificateMap['name']?.toString() ?? '',
                  imageUrl:
                  certificateMap['imageUrl']?.toString(),
                );
              }).toList(),
            );
          }).toList();
          var projectData = data?['projects'] ?? [];
          projectsList = List<Map<String, dynamic>>.from(projectData)
              .map((e) =>
              ProjectData(
                projectName: e['projectName'] ?? '',
                title: e['title'] ?? '',
                challengesAndSolutions: e['challengesAndSolutions'] ?? '',
                keyFeatures: e['keyFeatures'] ?? '',
                githubUrl: e['githubUrl'] ?? '',
                codeSnippet: e['codeSnippet'] ?? '',
                stackDescription: e['stackDescription'] ?? '',
                mediaFiles: [],
                mediaUrls: List<String>.from(e['mediaFiles'] ?? []),
              ))
              .toList();
          var expertiseData = data?['expertise'] ?? [];
          expertiseList = List<Map<String, dynamic>>.from(expertiseData)
              .map((section) => ExpertiseSectionData(
            sectionTitle: section['sectionTitle'] ?? '',
            items: (section['items'] as List<dynamic>? ?? [])
                .map((item) => ExpertiseItemData(
              title: item['title'] ?? '',
              iconUrl: item['iconUrl'],
              bulletPoints:
              List<String>.from(item['bulletPoints'] ?? []),
              levelOrPercentage:
              item['levelOrPercentage'] ?? '',
            ))
                .toList(),
          ))
              .toList();
          if (data != null && data.containsKey('dashboardImage')) {
            dashboardImageUrl = data['dashboardImage'];
            print("Dashboard URL from Firestore: $dashboardImageUrl");
          }
          profileName = data?['profileName'] ?? profileName;
          colam4 = data?['colam4'] ?? colam4;
          colam5 = data?['colam5'] ?? colam5;
          colam6 = data?['colam6'] ?? colam6;
          aboutMe = data?['aboutMe'] ?? aboutMe;
          aboutMeTitle = data?['aboutMeTitle'] ?? aboutMeTitle;
          operationalDomainTitle =
              data?['operationalDomainTitle'] ?? operationalDomainTitle;

          technicalStackTitle =
              data?['technicalStackTitle'] ?? technicalStackTitle;
          homeMenuTitle =
              data?['homeMenuTitle'] ?? homeMenuTitle;
          resumeMenuTitle =
              data?['resumeMenuTitle'] ?? resumeMenuTitle;
          projectMenuTitle =
              data?['projectMenuTitle'] ?? projectMenuTitle;
          experienceMenuTitle =
              data?['experienceMenuTitle'] ?? experienceMenuTitle;
          expertiseMenuTitle =
              data?['expertiseMenuTitle'] ?? expertiseMenuTitle;

          operationalDomain = data?['operationalDomain'] ?? operationalDomain;
          technicalStack = data?['technicalStack'] ?? technicalStack;

          emailAddress = data?['emailAddress'] ?? "";
          phoneNumber = data?['phoneNumber'] ?? "";
          linkedinUrl = data?['linkedinUrl'] ?? "";
          setState(() {
            if (data != null && data.containsKey('resumeUrl')) {
              resumePdfUrl = data['resumeUrl'];
              resumePdfName = data['resumeName'] ?? "";
              print("CV loaded: $resumePdfUrl");
            } else {
              print("No CV found in Firestore");
            }
          });
        }); //
        print("Data and Dashboard Image loaded successfully!");
      }
    } catch (e) {
      print("Error loading data: $e");
    }
  }

  String profileName = "ARIFUL'S PORTFOLIO";
  Uint8List? dashboardImageBytes;
  String? dashboardImageUrl;

  String? resumePdfUrl;
  String resumePdfName = "";
  Uint8List? resumePdfBytes;

  String colam4 = "4";
  String colam5 = "5";
  String colam6 = "6.";
  String aboutMe = "7.";
  String operationalDomain = "8.";
  String technicalStack = "";
  String aboutMeTitle = "About Me";
  String operationalDomainTitle = "Operational Domain";
  String technicalStackTitle = "Technical Stack";
  String homeMenuTitle = "Home";
  String resumeMenuTitle = "Resume/CV";
  String projectMenuTitle = "My Project";
  String experienceMenuTitle = "Experience";
  String expertiseMenuTitle = "Expertise";

  List<ExperienceData> experiencesList = [];
  List<ProjectData> projectsList = [];
  List<ExpertiseSectionData> expertiseList = [];

  Future<void> _launchURL(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch $urlString')),
        );
      }
    }
  }

  void _viewSelectedPdf() {
    if (resumePdfUrl == null || resumePdfUrl!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No PDF uploaded yet!'), backgroundColor: Colors.red),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PdfViewerPage(url: resumePdfUrl!),
      ),
    );
  }
  void _downloadPdf() {
    if (resumePdfUrl == null || resumePdfUrl!.isEmpty) return;
    if (kIsWeb) {
      html.AnchorElement anchor = html.AnchorElement(href: resumePdfUrl!);
      anchor.setAttribute("download", resumePdfName ?? "resume.pdf");
      anchor.click();
    }
  }

  void _downloadSelectedPdf() {
    if (resumePdfBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No PDF uploaded yet to download!'),
            backgroundColor: Colors.red),
      );
      return;
    }

    if (kIsWeb) {
      final blob = html.Blob([resumePdfBytes!], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute(
            "download", resumePdfName.isNotEmpty ? resumePdfName : "resume.pdf")
        ..click();
      html.Url.revokeObjectUrl(url);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
            'PDF downloading native to mobile storage requires path providers. Preview active on Web only.')),
      );
    }
  }
  void _showFullImageDialog(BuildContext context, Uint8List imageBytes, String title) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title, style: const TextStyle(fontSize: 16)),
              backgroundColor: const Color(0xFF000080),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: Image.memory(imageBytes, fit: BoxFit.contain),
            ),
          ],
        ),
      ),
    );
  }
  void _navigateToPersonalPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PersonalDetailsPage(
          currentName: profileName,
          currentMail: emailAddress,
          currentPhone: phoneNumber,
          currentLinkedin: linkedinUrl,
          currentColam4: colam4,
          currentColam5: colam5,
          currentColam6: colam6,
          currentAboutMe: aboutMe,
          currentOpDomain: operationalDomain,
          currentTechnicalStack: technicalStack,
          currentAboutMeTitle: aboutMeTitle,
          currentOperationalDomainTitle: operationalDomainTitle,
          currentTechnicalStackTitle: technicalStackTitle,
          currentHomeMenuTitle: homeMenuTitle,
          currentResumeMenuTitle: resumeMenuTitle,
          currentProjectMenuTitle: projectMenuTitle,
          currentExperienceMenuTitle: experienceMenuTitle,
          currentExpertiseMenuTitle: expertiseMenuTitle,
          currentExperiences: experiencesList,
          currentProjects: projectsList,
          currentPdfName: resumePdfName,
          currentExpertise: expertiseList,
          onNameUpdated: (newName) async {
            setState(() => profileName = newName);
            await _savePersonalInfo();
          },
          onImageUpdated: (newImageBytes) => setState(() => dashboardImageBytes = newImageBytes),
          onMailUpdated: (mail) async {
            setState(() => emailAddress = mail);
            await _savePersonalInfo();
          },
          onPhoneUpdated: (phone) async {
            setState(() => phoneNumber = phone);
            await _savePersonalInfo();
          },
          onLinkedinUpdated: (link) async {
            setState(() => linkedinUrl = link);
            await _savePersonalInfo();
          },
          onColam4Updated: (val) async {
            setState(() => colam4 = val);
            await _savePersonalInfo();
          },
          onColam5Updated: (val) async {
            setState(() => colam5 = val);
            await _savePersonalInfo();
          },
          onColam6Updated: (val) async {
            setState(() => colam6 = val);
            await _savePersonalInfo();
          },
          onAboutMeUpdated: (val) async {
            setState(() => aboutMe = val);
            await _savePersonalInfo();
          },
          onOpDomainUpdated: (val) async {
            setState(() => operationalDomain = val);
            await _savePersonalInfo();
          },
          onTechnicalStackUpdated: (val) async {
            setState(() => technicalStack = val);
            await _savePersonalInfo();
          },
          onAboutMeTitleUpdated: (val) async {
            setState(() => aboutMeTitle = val);
            await _savePersonalInfo();
          },

          onOperationalDomainTitleUpdated: (val) async {
            setState(() => operationalDomainTitle = val);
            await _savePersonalInfo();
          },

          onTechnicalStackTitleUpdated: (val) async {
            setState(() => technicalStackTitle = val);
            await _savePersonalInfo();
          },
          onHomeMenuTitleUpdated: (val) async {
            setState(() => homeMenuTitle = val);
            await _savePersonalInfo();
          },

          onResumeMenuTitleUpdated: (val) async {
            setState(() => resumeMenuTitle = val);
            await _savePersonalInfo();
          },

          onProjectMenuTitleUpdated: (val) async {
            setState(() => projectMenuTitle = val);
            await _savePersonalInfo();
          },

          onExperienceMenuTitleUpdated: (val) async {
            setState(() => experienceMenuTitle = val);
            await _savePersonalInfo();
          },

          onExpertiseMenuTitleUpdated: (val) async {
            setState(() => expertiseMenuTitle = val);
            await _savePersonalInfo();
          },
          onExperiencesUpdated: (updatedList) => setState(() => experiencesList = updatedList),
          onProjectsUpdated: (updatedProjList) => setState(() => projectsList = updatedProjList),
          onExpertiseUpdated: (updatedExpertiseList) => setState(() => expertiseList = updatedExpertiseList),
          onPdfUploaded: (bytes, name) {
            setState(() {
              resumePdfBytes = bytes;
              resumePdfName = name;
            });
          },
        ),
      ),
    );
  }

  void _showPasswordDialog(BuildContext context) {
    final TextEditingController passwordController =
    TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Admin Access"),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: "Enter Password",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF000080),
              ),
              onPressed: () async {
                final String password =
                passwordController.text.trim();

                if (password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Please enter password!"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  await FirebaseAuth.instance
                      .signInWithEmailAndPassword(
                    email: "mdarifulislamsub@gmail.com",
                    password: password,
                  );

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }

                  if (mounted) {
                    _navigateToPersonalPage();
                  }
                } on FirebaseAuthException catch (e) {
                  debugPrint("Firebase login error: ${e.code} - ${e.message}");

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "Firebase Error: ${e.code}\n${e.message ?? ''}",
                        ),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 8),
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint("Login error: $e");

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Login Error: $e"),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 8),
                      ),
                    );
                  }
                }
              },
              child: const Text(
                "Login",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }
  void _showProjectDisplayDialog(BuildContext context) {
    final PageController projectPageController = PageController();
    int activeProjectIndex = 0;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final double screenWidth =
                MediaQuery.of(dialogContext).size.width;

            final double screenHeight =
                MediaQuery.of(dialogContext).size.height;

            final double dialogWidth =
            screenWidth >= 1200
                ? screenWidth * 0.80
                : screenWidth * 0.92;

            return Dialog(
              insetPadding: const EdgeInsets.all(18),
              backgroundColor: const Color(0xFFF8F6FC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Container(
                width: dialogWidth,
                constraints: BoxConstraints(
                  maxHeight: screenHeight * 0.88,
                ),
                padding: const EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // =========================
                    // HEADER
                    // =========================
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            "My Dashboard Projects",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF000080),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: "Close",
                          onPressed: () {
                            Navigator.pop(dialogContext);
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),

                    const Divider(
                      thickness: 2,
                      height: 16,
                    ),

                    const SizedBox(height: 8),

                    // =========================
                    // PROJECT CONTENT
                    // =========================
                    projectsList.isEmpty
                        ? const Expanded(
                      child: Center(
                        child: Text(
                          "No projects added yet. Please configure from Personal Section.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    )
                        : Expanded(
                      child: PageView.builder(
                        controller: projectPageController,
                        itemCount: projectsList.length,
                        onPageChanged: (index) {
                          setDialogState(() {
                            activeProjectIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final ProjectData proj =
                          projectsList[index];

                          return SingleChildScrollView(
                            padding: const EdgeInsets.only(
                              left: 5,
                              right: 5,
                              bottom: 15,
                            ),
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                // Project name
                                Center(
                                  child: Text(
                                    proj.projectName.trim().isNotEmpty
                                        ? proj.projectName
                                        .trim()
                                        .toUpperCase()
                                        : "PROJECT NAME",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueAccent,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 6),

                                // Project title
                                Center(
                                  child: Text(
                                    proj.title.trim().isNotEmpty
                                        ? proj.title.trim()
                                        : "Title Not Added",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 18),

                                // Challenges + Key features
                                LayoutBuilder(
                                  builder:
                                      (
                                      context,
                                      constraints,
                                      ) {
                                    final bool twoColumns =
                                        constraints.maxWidth >= 700;

                                    if (twoColumns) {
                                      return Row(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child:
                                            _buildProjectInfoBox(
                                              "Challenges & Solutions:",
                                              proj.challengesAndSolutions,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child:
                                            _buildProjectInfoBox(
                                              "Key Features:",
                                              proj.keyFeatures,
                                            ),
                                          ),
                                        ],
                                      );
                                    }

                                    return Column(
                                      children: [
                                        _buildProjectInfoBox(
                                          "Challenges & Solutions:",
                                          proj.challengesAndSolutions,
                                        ),
                                        const SizedBox(height: 15),
                                        _buildProjectInfoBox(
                                          "Key Features:",
                                          proj.keyFeatures,
                                        ),
                                      ],
                                    );
                                  },
                                ),

                                const SizedBox(height: 18),

                                const Text(
                                  "Tech Stack:",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.black87,
                                  ),
                                ),

                                const SizedBox(height: 8),

                                const Wrap(
                                  spacing: 14,
                                  runSpacing: 10,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.bolt,
                                          color: Colors.blue,
                                        ),
                                        Text(" Flutter"),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.code,
                                          color: Colors.cyan,
                                        ),
                                        Text(" Dart"),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons
                                              .local_fire_department,
                                          color: Colors.orange,
                                        ),
                                        Text(" Firebase"),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.api,
                                          color: Colors.green,
                                        ),
                                        Text(" REST APIs"),
                                      ],
                                    ),
                                  ],
                                ),

                                // =========================
                                // LIVE DEMO GALLERY
                                // =========================
                                if (proj.mediaUrls.isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  const Text(
                                    "Live Demo Gallery:",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 9),
                                  SizedBox(
                                    height: 100,
                                    child: ListView.builder(
                                      scrollDirection:
                                      Axis.horizontal,
                                      itemCount:
                                      proj.mediaUrls.length,
                                      itemBuilder:
                                          (
                                          context,
                                          mediaIndex,
                                          ) {
                                        return Padding(
                                          padding:
                                          const EdgeInsets.only(
                                            right: 10,
                                          ),
                                          child: InkWell(
                                            borderRadius:
                                            BorderRadius.circular(
                                              10,
                                            ),
                                            onTap: () {
                                              _showProjectGalleryDialog(
                                                dialogContext,
                                                proj.mediaUrls,
                                                mediaIndex,
                                              );
                                            },
                                            child: Container(
                                              width: 100,
                                              decoration:
                                              BoxDecoration(
                                                color:
                                                Colors.white,
                                                borderRadius:
                                                BorderRadius.circular(
                                                  10,
                                                ),
                                                border:
                                                Border.all(
                                                  color:
                                                  Colors
                                                      .grey
                                                      .shade300,
                                                ),
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                BorderRadius.circular(
                                                  9,
                                                ),
                                                child: Image.network(
                                                  proj.mediaUrls[mediaIndex],
                                                  width: 100,
                                                  height: 100,
                                                  fit: BoxFit.cover,
                                                  loadingBuilder:
                                                      (
                                                      context,
                                                      child,
                                                      progress,
                                                      ) {
                                                    if (progress ==
                                                        null) {
                                                      return child;
                                                    }

                                                    return const Center(
                                                      child:
                                                      CircularProgressIndicator(
                                                        strokeWidth:
                                                        2,
                                                      ),
                                                    );
                                                  },
                                                  errorBuilder:
                                                      (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                      ) {
                                                    return const Center(
                                                      child: Icon(
                                                        Icons
                                                            .broken_image_outlined,
                                                        color:
                                                        Colors
                                                            .grey,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],

                                // =========================
                                // APP DESCRIPTION
                                // =========================
                                if (proj.codeSnippet
                                    .trim()
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 18),
                                  const Text(
                                    "Apps Description:",
                                    style: TextStyle(
                                      color: Colors.lightBlue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding:
                                    const EdgeInsets.all(15),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                      BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      proj.codeSnippet,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        height: 1.45,
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 8),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    if (projectsList.isNotEmpty) ...[
                      const SizedBox(height: 12),

                      // =========================
                      // PREMIUM RESPONSIVE FOOTER
                      // =========================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFFE4DFF2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final bool compactFooter =
                                constraints.maxWidth < 700;

                            Widget githubButton() {
                              final String githubUrl =
                              projectsList[activeProjectIndex]
                                  .githubUrl
                                  .trim();

                              if (githubUrl.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              return ElevatedButton.icon(
                                onPressed: () {
                                  _launchURL(githubUrl);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  minimumSize: const Size(
                                    170,
                                    44,
                                  ),
                                  padding:
                                  const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.link_rounded,
                                  color: Colors.white,
                                  size: 19,
                                ),
                                label: const Text(
                                  "Open GitHub Repo",
                                  maxLines: 1,
                                  overflow:
                                  TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }

                            Widget projectIndicators() {
                              if (projectsList.length <= 1) {
                                return const SizedBox.shrink();
                              }

                              return SingleChildScrollView(
                                scrollDirection:
                                Axis.horizontal,
                                child: Row(
                                  mainAxisSize:
                                  MainAxisSize.min,
                                  children: List.generate(
                                    projectsList.length,
                                        (index) {
                                      final bool selected =
                                          index ==
                                              activeProjectIndex;

                                      return Padding(
                                        padding:
                                        const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: InkWell(
                                          borderRadius:
                                          BorderRadius.circular(
                                            50,
                                          ),
                                          onTap: () {
                                            projectPageController
                                                .animateToPage(
                                              index,
                                              duration:
                                              const Duration(
                                                milliseconds:
                                                300,
                                              ),
                                              curve:
                                              Curves.easeInOut,
                                            );
                                          },
                                          child: AnimatedContainer(
                                            duration:
                                            const Duration(
                                              milliseconds: 250,
                                            ),
                                            width: 40,
                                            height: 40,
                                            alignment:
                                            Alignment.center,
                                            decoration: BoxDecoration(
                                              color:
                                              selected
                                                  ? const Color(
                                                0xFF000080,
                                              )
                                                  : const Color(
                                                0xFFF1F2F7,
                                              ),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color:
                                                selected
                                                    ? const Color(
                                                  0xFF000080,
                                                )
                                                    : Colors
                                                    .grey
                                                    .shade300,
                                              ),
                                              boxShadow:
                                              selected
                                                  ? [
                                                BoxShadow(
                                                  color:
                                                  const Color(
                                                    0xFF000080,
                                                  ).withOpacity(
                                                    0.18,
                                                  ),
                                                  blurRadius:
                                                  8,
                                                  offset:
                                                  const Offset(
                                                    0,
                                                    3,
                                                  ),
                                                ),
                                              ]
                                                  : null,
                                            ),
                                            child: Text(
                                              "${index + 1}",
                                              style: TextStyle(
                                                color:
                                                selected
                                                    ? Colors.white
                                                    : Colors
                                                    .black87,
                                                fontWeight:
                                                FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            }

                            Widget closeButton() {
                              return ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(
                                    dialogContext,
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                  const Color(0xFF000080),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  minimumSize: const Size(
                                    105,
                                    44,
                                  ),
                                  padding:
                                  const EdgeInsets.symmetric(
                                    horizontal: 22,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  "Close",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              );
                            }

                            // Desktop / laptop footer
                            if (!compactFooter) {
                              return Row(
                                crossAxisAlignment:
                                CrossAxisAlignment.center,
                                children: [
                                  githubButton(),

                                  const SizedBox(width: 18),

                                  Expanded(
                                    child: Align(
                                      alignment:
                                      Alignment.centerLeft,
                                      child:
                                      projectIndicators(),
                                    ),
                                  ),

                                  const SizedBox(width: 18),

                                  closeButton(),
                                ],
                              );
                            }

                            // Small window footer
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    if (projectsList[
                                    activeProjectIndex]
                                        .githubUrl
                                        .trim()
                                        .isNotEmpty)
                                      Expanded(
                                        child: githubButton(),
                                      ),

                                    if (projectsList[
                                    activeProjectIndex]
                                        .githubUrl
                                        .trim()
                                        .isNotEmpty)
                                      const SizedBox(width: 10),

                                    closeButton(),
                                  ],
                                ),

                                if (projectsList.length > 1) ...[
                                  const SizedBox(height: 12),
                                  Center(
                                    child:
                                    projectIndicators(),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      projectPageController.dispose();
    });
  }
  void _showProjectGalleryDialog(
      BuildContext context,
      List<String> imageUrls,
      int initialIndex,
      ) {
    final PageController controller =
    PageController(initialPage: initialIndex);

    int currentIndex = initialIndex;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.85,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              "${currentIndex + 1}/${imageUrls.length}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PageView.builder(
                            controller: controller,
                            itemCount: imageUrls.length,
                            onPageChanged: (index) {
                              setDialogState(() {
                                currentIndex = index;
                              });
                            },
                            itemBuilder: (context, index) {
                              return InteractiveViewer(
                                minScale: 0.5,
                                maxScale: 5,
                                child: Image.network(
                                  imageUrls[index],
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.contain,
                                ),
                              );
                            },
                          ),

                          if (currentIndex > 0)
                            Positioned(
                              left: 10,
                              child: IconButton(
                                onPressed: () {
                                  controller.previousPage(
                                    duration:
                                    const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                                icon: const Icon(Icons.arrow_back_ios),
                              ),
                            ),

                          if (currentIndex < imageUrls.length - 1)
                            Positioned(
                              right: 10,
                              child: IconButton(
                                onPressed: () {
                                  controller.nextPage(
                                    duration:
                                    const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                },
                                icon: const Icon(Icons.arrow_forward_ios),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProjectInfoBox(String title, String content) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF000080))),
          const SizedBox(height: 5),
          Text(content.isNotEmpty ? content : "N/A"),
        ],
      ),
    );
  }

  void _showExperienceDisplayDialog(BuildContext context) {
    final PageController experiencePageController = PageController();
    int activeExperienceIndex = 0;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final double screenWidth =
                MediaQuery.of(dialogContext).size.width;

            final double screenHeight =
                MediaQuery.of(dialogContext).size.height;

            final double dialogWidth =
            screenWidth >= 1200
                ? screenWidth * 0.80
                : screenWidth * 0.92;

            void showCurrentProfile() {
              if (experiencesList.isEmpty) return;

              final ExperienceData experience =
              experiencesList[activeExperienceIndex];

              showDialog(
                context: dialogContext,
                builder: (profileContext) {
                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    titlePadding: EdgeInsets.zero,
                    title: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF000080),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.account_circle_rounded,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              "Experience Profile",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              Navigator.pop(profileContext);
                            },
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    content: SizedBox(
                      width: 420,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            experience.companyName.trim().isNotEmpty
                                ? experience.companyName
                                : "Company name not provided",
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueAccent,
                            ),
                          ),

                          const SizedBox(height: 10),

                          Text(
                            "Total Service: "
                                "${experience.date.trim().isNotEmpty ? experience.date : 'N/A'}",
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),

                          if (experience.designations.isNotEmpty) ...[
                            const SizedBox(height: 16),

                            const Text(
                              "Career Progression",
                              style: TextStyle(
                                color: Color(0xFF000080),
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 8),

                            ...List.generate(
                              experience.designations.length,
                                  (index) {
                                final designation =
                                experience.designations[index];

                                return Padding(
                                  padding:
                                  const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor:
                                        const Color(0xFF000080),
                                        child: Text(
                                          "${index + 1}",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight:
                                            FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          designation.title
                                              .trim()
                                              .isNotEmpty
                                              ? designation.title
                                              : "Designation not provided",
                                          style: const TextStyle(
                                            fontWeight:
                                            FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            }

            return Dialog(
              insetPadding: const EdgeInsets.all(18),
              backgroundColor: const Color(0xFFF8F6FC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Container(
                width: dialogWidth,
                constraints: BoxConstraints(
                  maxHeight: screenHeight * 0.88,
                ),
                padding: const EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    // =========================
                    // HEADER
                    // =========================
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            "Work Experience & Certificates",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF000080),
                            ),
                          ),
                        ),

                        IconButton(
                          tooltip: "Close",
                          onPressed: () {
                            Navigator.pop(dialogContext);
                          },
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),

                    const Divider(
                      thickness: 2,
                      height: 16,
                    ),

                    const SizedBox(height: 8),

                    // =========================
                    // EXPERIENCE CONTENT
                    // =========================
                    experiencesList.isEmpty
                        ? const Expanded(
                      child: Center(
                        child: Text(
                          "No experience added yet. "
                              "Please add experience from Personal Section.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    )
                        : Expanded(
                        child: ScrollConfiguration(
                          behavior: const MaterialScrollBehavior().copyWith(
                            dragDevices: {
                              PointerDeviceKind.touch,
                              PointerDeviceKind.mouse,
                              PointerDeviceKind.trackpad,
                            },
                          ),
                          child: PageView.builder(
                            controller: experiencePageController,
                            scrollDirection: Axis.horizontal,
                            physics: const PageScrollPhysics(),
                        itemCount: experiencesList.length,
                        onPageChanged: (index) {
                          setDialogState(() {
                            activeExperienceIndex =
                                index;
                          });
                        },
                            itemBuilder: (context, experienceIndex) {
                              final ExperienceData exp =
                              experiencesList[experienceIndex];

                              return ScrollConfiguration(
                                behavior: const MaterialScrollBehavior().copyWith(
                                  dragDevices: {
                                    PointerDeviceKind.touch,
                                    PointerDeviceKind.mouse,
                                    PointerDeviceKind.trackpad,
                                  },
                                ),
                                child: SingleChildScrollView(
                                  physics: const ClampingScrollPhysics(),
                                  padding: const EdgeInsets.only(
                                    left: 5,
                                    right: 5,
                                    bottom: 16,
                                  ),
                                  child: Card(
                                    margin: const EdgeInsets.only(
                                      bottom: 8,
                                    ),
                                    elevation: 3,
                                    color: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            exp.companyName.trim().isNotEmpty
                                                ? exp.companyName.trim().toUpperCase()
                                                : "COMPANY NAME",
                                            style: const TextStyle(
                                              fontSize: 19,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blueAccent,
                                            ),
                                          ),

                                          const SizedBox(height: 8),

                                          Text(
                                            "Total Service: "
                                                "${exp.date.trim().isNotEmpty ? exp.date : 'N/A'}",
                                            style: const TextStyle(
                                              color: Colors.grey,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),

                                          const SizedBox(height: 16),

                                          if (exp.designations.isNotEmpty) ...[
                                            const Text(
                                              "Career Progression",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF000080),
                                              ),
                                            ),

                                            const SizedBox(height: 10),

                                            ...List.generate(
                                              exp.designations.length,
                                                  (designationIndex) {
                                                final designation =
                                                exp.designations[designationIndex];

                                                final String dateText = [
                                                  if (designation.fromDate.trim().isNotEmpty)
                                                    designation.fromDate.trim(),
                                                  if (designation.toDate.trim().isNotEmpty)
                                                    designation.toDate.trim(),
                                                ].join(" — ");

                                                return Container(
                                                  width: double.infinity,
                                                  margin: const EdgeInsets.only(
                                                    bottom: 10,
                                                  ),
                                                  padding: const EdgeInsets.all(14),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF7F8FF),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: const Color(0xFF000080)
                                                          .withOpacity(0.18),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      CircleAvatar(
                                                        radius: 18,
                                                        backgroundColor:
                                                        const Color(0xFF000080),
                                                        child: Text(
                                                          "${designationIndex + 1}",
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),

                                                      const SizedBox(width: 12),

                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                          CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              designation.title.trim().isNotEmpty
                                                                  ? designation.title
                                                                  : "Designation not provided",
                                                              style: const TextStyle(
                                                                fontSize: 15,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),

                                                            if (dateText.isNotEmpty) ...[
                                                              const SizedBox(height: 5),
                                                              Text(
                                                                dateText,
                                                                style: const TextStyle(
                                                                  color: Colors.black54,
                                                                ),
                                                              ),
                                                            ],

                                                            if (designation.serviceLength
                                                                .trim()
                                                                .isNotEmpty) ...[
                                                              const SizedBox(height: 5),
                                                              Text(
                                                                "Service Length: "
                                                                    "${designation.serviceLength}",
                                                                style: const TextStyle(
                                                                  color: Color(0xFF000080),
                                                                  fontWeight: FontWeight.w600,
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ] else ...[
                                            Text(
                                              "Designation: "
                                                  "${exp.designation.trim().isNotEmpty ? exp.designation : 'N/A'}",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],

                                          const SizedBox(height: 14),

                                          const Text(
                                            "Description:",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),

                                          const SizedBox(height: 5),

                                          Text(
                                            exp.description.trim().isNotEmpty
                                                ? exp.description
                                                : "No description provided.",
                                            style: const TextStyle(
                                              height: 1.45,
                                            ),
                                          ),

                                          if (exp.certificates.isNotEmpty) ...[
                                            const SizedBox(height: 18),

                                            const Text(
                                              "Attached Certificates (Click to view):",
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: Colors.black87,
                                              ),
                                            ),

                                            const SizedBox(height: 9),

                                            SizedBox(
                                              height: 86,
                                              child: ListView.builder(
                                                scrollDirection: Axis.horizontal,
                                                itemCount: exp.certificates.length,
                                                itemBuilder: (
                                                    context,
                                                    certificateIndex,
                                                    ) {
                                                  final certificate =
                                                  exp.certificates[certificateIndex];

                                                  return Padding(
                                                    padding: const EdgeInsets.only(
                                                      right: 12,
                                                    ),
                                                    child: InkWell(
                                                      borderRadius:
                                                      BorderRadius.circular(10),
                                                      onTap: () {
                                                        _showCertificateGalleryDialog(
                                                          dialogContext,
                                                          exp.certificates,
                                                          certificateIndex,
                                                        );
                                                      },
                                                      child: Tooltip(
                                                        message: certificate.name,
                                                        child: Container(
                                                          width: 86,
                                                          decoration: BoxDecoration(
                                                            color: Colors.white,
                                                            border: Border.all(
                                                              color: Colors.grey.shade300,
                                                            ),
                                                            borderRadius:
                                                            BorderRadius.circular(10),
                                                          ),
                                                          child: ClipRRect(
                                                            borderRadius:
                                                            BorderRadius.circular(9),
                                                            child: certificate.bytes != null
                                                                ? Image.memory(
                                                              certificate.bytes!,
                                                              fit: BoxFit.cover,
                                                            )
                                                                : certificate.imageUrl != null &&
                                                                certificate
                                                                    .imageUrl!.isNotEmpty
                                                                ? Image.network(
                                                              certificate.imageUrl!,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (
                                                                  context,
                                                                  error,
                                                                  stackTrace,
                                                                  ) {
                                                                return const Icon(
                                                                  Icons
                                                                      .broken_image_outlined,
                                                                  color: Colors.grey,
                                                                );
                                                              },
                                                            )
                                                                : const Icon(
                                                              Icons.image_outlined,
                                                              color: Colors.grey,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                      ),
                    ),
                    ),
                    if (experiencesList.isNotEmpty) ...[
                      const SizedBox(height: 12),

                      // =========================
                      // PREMIUM RESPONSIVE FOOTER
                      // =========================
                      Container(
                        width: double.infinity,
                        padding:
                        const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                          BorderRadius.circular(14),
                          border: Border.all(
                            color:
                            const Color(0xFFE4DFF2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withOpacity(0.06),
                              blurRadius: 14,
                              offset:
                              const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: LayoutBuilder(
                          builder:
                              (context, constraints) {
                            final bool compactFooter =
                                constraints.maxWidth <
                                    700;

                            Widget profileButton() {
                              return ElevatedButton.icon(
                                onPressed:
                                showCurrentProfile,
                                style:
                                ElevatedButton.styleFrom(
                                  backgroundColor:
                                  Colors.black,
                                  foregroundColor:
                                  Colors.white,
                                  elevation: 0,
                                  minimumSize:
                                  const Size(
                                    155,
                                    44,
                                  ),
                                  padding:
                                  const EdgeInsets.symmetric(
                                    horizontal:
                                    18,
                                    vertical:
                                    12,
                                  ),
                                  shape:
                                  RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons
                                      .account_circle_outlined,
                                  color: Colors.white,
                                  size: 19,
                                ),
                                label: const Text(
                                  "Profile View",
                                  maxLines: 1,
                                  overflow:
                                  TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight:
                                    FontWeight.bold,
                                  ),
                                ),
                              );
                            }

                            Widget experienceIndicators() {
                              if (experiencesList.length <=
                                  1) {
                                return const SizedBox
                                    .shrink();
                              }

                              return SingleChildScrollView(
                                scrollDirection:
                                Axis.horizontal,
                                child: Row(
                                  mainAxisSize:
                                  MainAxisSize.min,
                                  children: List.generate(
                                    experiencesList.length,
                                        (index) {
                                      final bool selected =
                                          index ==
                                              activeExperienceIndex;

                                      return Padding(
                                        padding:
                                        const EdgeInsets.symmetric(
                                          horizontal:
                                          4,
                                        ),
                                        child: InkWell(
                                          borderRadius:
                                          BorderRadius.circular(
                                            50,
                                          ),
                                          onTap: () {
                                            experiencePageController
                                                .animateToPage(
                                              index,
                                              duration:
                                              const Duration(
                                                milliseconds:
                                                300,
                                              ),
                                              curve:
                                              Curves.easeInOut,
                                            );
                                          },
                                          child:
                                          AnimatedContainer(
                                            duration:
                                            const Duration(
                                              milliseconds:
                                              250,
                                            ),
                                            width: 40,
                                            height:
                                            40,
                                            alignment:
                                            Alignment.center,
                                            decoration:
                                            BoxDecoration(
                                              color:
                                              selected
                                                  ? const Color(
                                                0xFF000080,
                                              )
                                                  : const Color(
                                                0xFFF1F2F7,
                                              ),
                                              shape:
                                              BoxShape.circle,
                                              border: Border.all(
                                                color:
                                                selected
                                                    ? const Color(
                                                  0xFF000080,
                                                )
                                                    : Colors.grey.shade300,
                                              ),
                                              boxShadow:
                                              selected
                                                  ? [
                                                BoxShadow(
                                                  color: const Color(
                                                    0xFF000080,
                                                  ).withOpacity(
                                                    0.18,
                                                  ),
                                                  blurRadius:
                                                  8,
                                                  offset:
                                                  const Offset(
                                                    0,
                                                    3,
                                                  ),
                                                ),
                                              ]
                                                  : null,
                                            ),
                                            child:
                                            Text(
                                              "${index + 1}",
                                              style:
                                              TextStyle(
                                                color:
                                                selected
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontWeight:
                                                FontWeight.bold,
                                                fontSize:
                                                13,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            }

                            Widget closeButton() {
                              return ElevatedButton(
                                onPressed: () {
                                  Navigator.pop(
                                    dialogContext,
                                  );
                                },
                                style:
                                ElevatedButton.styleFrom(
                                  backgroundColor:
                                  const Color(
                                    0xFF000080,
                                  ),
                                  foregroundColor:
                                  Colors.white,
                                  elevation: 0,
                                  minimumSize:
                                  const Size(
                                    105,
                                    44,
                                  ),
                                  padding:
                                  const EdgeInsets.symmetric(
                                    horizontal:
                                    22,
                                    vertical:
                                    12,
                                  ),
                                  shape:
                                  RoundedRectangleBorder(
                                    borderRadius:
                                    BorderRadius.circular(
                                      12,
                                    ),
                                  ),
                                ),
                                child: const Text(
                                  "Close",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight:
                                    FontWeight.bold,
                                  ),
                                ),
                              );
                            }

                            // Desktop / laptop
                            if (!compactFooter) {
                              return Row(
                                crossAxisAlignment:
                                CrossAxisAlignment
                                    .center,
                                children: [
                                  profileButton(),

                                  const SizedBox(
                                    width: 18,
                                  ),

                                  Expanded(
                                    child: Align(
                                      alignment:
                                      Alignment
                                          .centerLeft,
                                      child:
                                      experienceIndicators(),
                                    ),
                                  ),

                                  const SizedBox(
                                    width: 18,
                                  ),

                                  closeButton(),
                                ],
                              );
                            }

                            // Small window
                            return Column(
                              mainAxisSize:
                              MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child:
                                      profileButton(),
                                    ),

                                    const SizedBox(
                                      width: 10,
                                    ),

                                    closeButton(),
                                  ],
                                ),

                                if (experiencesList
                                    .length >
                                    1) ...[
                                  const SizedBox(
                                    height: 12,
                                  ),
                                  Center(
                                    child:
                                    experienceIndicators(),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      experiencePageController.dispose();
    });
  }
  Future<void> _checkInternetAgain() async {
    if (!mounted) return;

    setState(() {
      _isCheckingInternet = true;
    });

    bool connected = false;

    try {
      connected = await _internetConnection.hasInternetAccess;
    } catch (_) {
      connected = false;
    }

    if (!mounted) return;

    setState(() {
      _hasInternet = connected;
      _isCheckingInternet = false;
    });

    if (connected) {
      _fetchData();
      _loadDataFromFirestore();
    }
  }

  Widget _buildCheckingInternetScreen() {
    return const Scaffold(
      backgroundColor: Color(0xFFF7F8FC),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: Color(0xFF000080),
            ),
            SizedBox(height: 20),
            Text(
              "Checking internet connection...",
              style: TextStyle(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 35,
                  vertical: 45,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE8EAFD),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        size: 52,
                        color: Color(0xFF000080),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      "No Internet Connection",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Please check your Wi-Fi or mobile data connection. "
                          "The portfolio will reconnect automatically when internet is available.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _checkInternetAgain,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF000080),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white,
                        ),
                        label: const Text(
                          "Try Again",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.sync_rounded,
                          size: 18,
                          color: Colors.green,
                        ),
                        SizedBox(width: 7),
                        Text(
                          "Automatic reconnection enabled",
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    if (_isCheckingInternet) {
      return _buildCheckingInternetScreen();
    }

    if (!_hasInternet) {
      return _buildOfflineScreen();
    }

    final double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,

      // STABLE Menu Bar
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 40,
            vertical: 20,
          ),
          color: const Color(0xFF000080),
          child: Row(
            children: [
              Text(
                profileName.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              const Spacer(),

              ...[
                homeMenuTitle,
                resumeMenuTitle,
                projectMenuTitle,
                experienceMenuTitle,
                expertiseMenuTitle,
              ].map(
                    (e) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.15),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      if (e == homeMenuTitle) {
                        // Home বাটনে ক্লিক করলে নতুন পেজ ওপেন হবে
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HomeNewPage(), // আপনার নতুন পেজের নাম
                          ),
                        );
                        return;
                      }
                      if (e == resumeMenuTitle) {
                        _showCvDialog(context);
                        return;
                      }
                      if (e == experienceMenuTitle) {
                        _showExperienceDisplayDialog(context);
                        return;
                      }
                      if (e == projectMenuTitle) {
                        _showProjectDisplayDialog(context);
                        return;
                      }
                      if (e == expertiseMenuTitle) {
                        _showExpertiseDisplayDialog(context);
                      }
                    },
                    child: Text(
                      e,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 12),

              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.menu,
                  color: Colors.white,
                  size: 30,
                ),
                offset: const Offset(0, 50),
                onSelected: (value) {
                  if (value == 'Personal') {
                    _showPasswordDialog(context);
                  }
                },
                itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'Personal',
                    child: Row(
                      children: [
                        Icon(
                          Icons.admin_panel_settings,
                          color: Color(0xFF000080),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Administrator',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF000080),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const PopupMenuItem<String>(
                    value: 'Settings',
                    child: Row(
                      children: [
                        Icon(
                          Icons.settings,
                          color: Color(0xFF000080),
                        ),
                        SizedBox(width: 10),
                        Text('Settings'),
                      ],
                    ),
                  ),

                  const PopupMenuItem<String>(
                    value: 'HelpDesk',
                    child: Row(
                      children: [
                        Icon(
                          Icons.help_outline,
                          color: Color(0xFF000080),
                        ),
                        SizedBox(width: 10),
                        Text('Help Desk'),
                      ],
                    ),
                  ),

                  const PopupMenuItem<String>(
                    value: 'Support',
                    child: Row(
                      children: [
                        Icon(
                          Icons.support_agent,
                          color: Color(0xFF000080),
                        ),
                        SizedBox(width: 10),
                        Text('Support'),
                      ],
                    ),
                  ),

                  const PopupMenuItem<String>(
                    value: 'ContactDeveloper',
                    child: Row(
                      children: [
                        Icon(
                          Icons.code,
                          color: Color(0xFF000080),
                        ),
                        SizedBox(width: 10),
                        Text('Contact Developer'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),

      body: InteractiveViewer(
        transformationController: _homeViewController,
        boundaryMargin: const EdgeInsets.all(0),
        minScale: 0.5,
        maxScale: 1.0,
        panEnabled: true,
        constrained: false,
        child: SizedBox(
          width: screenWidth < 1200 ? 1200 : screenWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 60,
              vertical: 40,
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildHeroContent(context),
                    ),
                    const SizedBox(width: 40),
                    Expanded(
                      child: Container(
                        height: 350,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(20),
                          image: (dashboardImageUrl != null &&
                              dashboardImageUrl!.trim().isNotEmpty)
                              ? DecorationImage(
                            image: NetworkImage(
                              dashboardImageUrl!.trim(),
                            ),
                            fit: BoxFit.cover,
                          )
                              : null,
                        ),
                        child: (dashboardImageUrl == null ||
                            dashboardImageUrl!.trim().isEmpty)
                            ? const Center(
                          child: Icon(
                            Icons.image,
                            size: 60,
                            color: Colors.grey,
                          ),
                        )
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 80),
                _buildFooterSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
  double _expertiseProgress(String value) {
    final String normalized = value.trim().toLowerCase();

    final RegExpMatch? match =
    RegExp(r'(\d+(?:\.\d+)?)').firstMatch(normalized);

    if (match != null) {
      final double percentage =
          double.tryParse(match.group(1)!) ?? 0;

      return (percentage / 100)
          .clamp(0.0, 1.0)
          .toDouble();
    }

    if (normalized.contains('expert')) return 0.95;
    if (normalized.contains('advanced')) return 0.80;
    if (normalized.contains('intermediate')) return 0.60;
    if (normalized.contains('beginner')) return 0.35;

    return 0.0;
  }
  Future<void> _showExpertiseDisplayDialog(BuildContext context) async {
    final Map<String, dynamic> footerData = {
      'approachTitle': 'My Approach',
      'approachDescription':
      'I combine logistics domain knowledge with modern technology to create solutions that are efficient, scalable, and make a real impact in business.',
      'logisticsValue': '6+',
      'logisticsLabel': 'Years Experience in Logistics',
      'developmentValue': '3+',
      'developmentLabel': 'Years Experience in Development',
      'projectsValue': '20+',
      'projectsLabel': 'Projects Completed',
      'satisfactionValue': '100%',
      'satisfactionLabel': 'Client Satisfaction',
      'buttonText': 'View My Projects',
    };

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('my_portfolio')
          .doc('user_data')
          .get();

      final dynamic savedFooter =
      snapshot.data()?['expertiseFooter'];

      if (savedFooter is Map) {
        footerData.addAll(
          Map<String, dynamic>.from(savedFooter),
        );
      }
    } catch (e) {
      debugPrint('Expertise footer load error: $e');
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFF8FAFC),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.fromLTRB(
            20,
            20,
            20,
            05,
          ),
          child: Column(
            children: [
              // Header Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "MY EXPERTISE",
                        style: TextStyle(color: Color(0xFF000080), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Where Logistics Meets Technology",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
              const Divider(height: 30, thickness: 1),

              Expanded(
                child: ListView.builder(
                  itemCount: expertiseList.length,
                  itemBuilder: (context, index) {

                    final section = expertiseList[index];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding:
                          const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            section.sectionTitle.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF000080),
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),

                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: section.items.map((item) {
                            return Container(
                              width: 240,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.grey.shade200,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                    Colors.black.withOpacity(0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius:
                                          BorderRadius.circular(8),
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                          BorderRadius.circular(8),
                                          child: item.iconBytes != null
                                              ? Image.memory(
                                            item.iconBytes!,
                                            fit: BoxFit.cover,
                                          )
                                              : (item.iconUrl != null &&
                                              item.iconUrl!
                                                  .isNotEmpty)
                                              ? Image.network(
                                            item.iconUrl!,
                                            fit: BoxFit.cover,
                                            errorBuilder: (
                                                context,
                                                error,
                                                stackTrace,
                                                ) {
                                              return const Icon(
                                                Icons.star,
                                                color: Color(
                                                  0xFF000080,
                                                ),
                                              );
                                            },
                                          )
                                              : const Icon(
                                            Icons.star,
                                            size: 24,
                                            color: Color(
                                              0xFF000080,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 12),

                                  ...item.bulletPoints.map((point) {
                                    return Padding(
                                      padding:
                                      const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "• ",
                                            style: TextStyle(
                                              color: Color(0xFF000080),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              point.toString(),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                Colors.grey.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),

                                  const SizedBox(height: 14),

                                  ClipRRect(
                                    borderRadius:
                                    BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: _expertiseProgress(
                                        item.levelOrPercentage,
                                      ),
                                      backgroundColor:
                                      Colors.blue.shade50,
                                      color: const Color(0xFF000080),
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 24),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              _buildExpertiseFooter(
                context,
                footerData,
              ),

            ],
          ),
        ),
      ),
    );
  }
  Widget _buildExpertiseFooter(
      BuildContext context,
      Map<String, dynamic> footerData,
      ) {
    final List<Map<String, dynamic>> stats = [
      {
        'icon': Icons.business_center_outlined,
        'value': footerData['logisticsValue']?.toString() ?? '',
        'label': footerData['logisticsLabel']?.toString() ?? '',
      },
      {
        'icon': Icons.code_rounded,
        'value': footerData['developmentValue']?.toString() ?? '',
        'label': footerData['developmentLabel']?.toString() ?? '',
      },
      {
        'icon': Icons.assignment_outlined,
        'value': footerData['projectsValue']?.toString() ?? '',
        'label': footerData['projectsLabel']?.toString() ?? '',
      },
      {
        'icon': Icons.people_outline_rounded,
        'value': footerData['satisfactionValue']?.toString() ?? '',
        'label': footerData['satisfactionLabel']?.toString() ?? '',
      },
    ];

    return Container(
      height: 92,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE6E0F5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final bool showApproachDescription =
              constraints.maxWidth >= 1200;
          final bool useHorizontalScroll =
              constraints.maxWidth < 1050;

          Widget buildApproach() {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEDE9FE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Color(0xFF5B21B6),
                    size: 23,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        footerData['approachTitle']?.toString() ??
                            'My Approach',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF4C1D95),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),

                      if (showApproachDescription) ...[
                        const SizedBox(height: 3),
                        Text(
                          footerData['approachDescription']
                              ?.toString() ??
                              '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 11,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }

          Widget buildStat(Map<String, dynamic> stat) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEDE9FE),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    stat['icon'] as IconData,
                    color: const Color(0xFF5B21B6),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        stat['value']?.toString() ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF5B21B6),
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stat['label']?.toString() ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 10.5,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          Widget buildProjectButton() {
            return SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();

                  Future.delayed(
                    const Duration(milliseconds: 150),
                        () {
                      if (mounted) {
                        _showProjectDisplayDialog(this.context);
                      }
                    },
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6D28D9),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  size: 19,
                  color: Colors.white,
                ),
                label: Text(
                  footerData['buttonText']?.toString() ??
                      'View My Projects',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }

          if (!useHorizontalScroll) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: showApproachDescription ? 270 : 190,
                  child: buildApproach(),
                ),
                const SizedBox(width: 16),

                ...stats.map(
                      (stat) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: buildStat(stat),
                    ),
                  ),
                ),

                SizedBox(
                  width: 180,
                  child: buildProjectButton(),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  child: buildApproach(),
                ),
                const SizedBox(width: 18),

                ...stats.map(
                      (stat) => Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: SizedBox(
                      width: 165,
                      child: buildStat(stat),
                    ),
                  ),
                ),

                SizedBox(
                  width: 180,
                  child: buildProjectButton(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  void _showCvDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.picture_as_pdf, size: 60, color: Color(0xFF000080)),
                const SizedBox(height: 20),
                Text(
                  ((resumePdfUrl?.trim().isNotEmpty ?? false) ||
                      resumePdfBytes != null)
                      ? "Resume / CV Loaded"
                      : "No CV Uploaded",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (resumePdfName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(resumePdfName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF000080),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      if (resumePdfUrl != null && resumePdfUrl!.isNotEmpty) {
                        html.window.open(resumePdfUrl!, '_blank');
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Link not found!")),
                        );
                      }
                    },
                    child: const Text(
                      "View CV",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (resumePdfUrl != null && resumePdfUrl!.isNotEmpty) {
                        final anchor = html.AnchorElement(href: resumePdfUrl!)
                          ..setAttribute("download", resumePdfName.isNotEmpty ? resumePdfName : "resume.pdf")
                          ..setAttribute("target", "_blank")
                          ..click();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Download link not found!")),
                        );
                      }
                    },
                    child: const Text("Download", style: TextStyle(color: Color(0xFF000080))),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooterSection() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _footerItem(
        technicalStackTitle,
        technicalStack.isNotEmpty
            ? technicalStack
            : "Flutter, Dart, Firebase, REST APIs, Git.",
      ),
      _footerItem(
        operationalDomainTitle,
        operationalDomain,
      ),
      _footerItem(
        aboutMeTitle,
        aboutMe,
      ),
    ],
  );

  Widget _footerItem(String title, String content) => Expanded(
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Divider(color: Colors.black, thickness: 2),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            const SizedBox(height: 5),
            Text(content, style: const TextStyle(color: Colors.black54, fontSize: 16))
          ])));

  Widget _buildHeroContent(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(colam4, style: const TextStyle(color: Colors.orange)),
      Text(colam5, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
      Text(colam6),
      const SizedBox(height: 20),
      ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF000080), padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20)),
          onPressed: () {
            _showContactDialog(context);
          },
          child: const Text("Contact Now", style: TextStyle(color: Colors.white))),
    ],
  );

  void _showContactDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            width: 350,
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Contact Information", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 25),

                // Mail Option
                _contactOption(Icons.mail, "Mail", Colors.blue, () {
                  if (emailAddress.isNotEmpty) _launchURL("mailto:$emailAddress");
                }),
                // WhatsApp Option
                _contactOption(
                  Icons.phone,
                  "WhatsApp",
                  Colors.green,
                      () async {
                    if (phoneNumber.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("WhatsApp number not found!"),
                        ),
                      );
                      return;
                    }

                    final String cleanNumber =
                    phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');

                    final bool isMobile =
                        defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.iOS;

                    final Uri whatsappUrl = isMobile
                        ? Uri.parse("https://wa.me/$cleanNumber")
                        : Uri.parse(
                      "https://web.whatsapp.com/send?phone=$cleanNumber",
                    );

                    final bool opened = await launchUrl(
                      whatsappUrl,
                      mode: LaunchMode.externalApplication,
                    );

                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Could not open WhatsApp!"),
                        ),
                      );
                    }
                  },
                ),
                // LinkedIn Option
                _contactOption(Icons.link, "LinkedIn", Colors.indigo, () {
                  if (linkedinUrl.isNotEmpty) {
                    String formattedUrl = linkedinUrl.startsWith("http") ? linkedinUrl : "https://$linkedinUrl";
                    _launchURL(formattedUrl);
                  }
                }),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Close", style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, String fieldName, String currentValue) {
    TextEditingController controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit $fieldName"),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              _updateField(fieldName, controller.text);
              Navigator.pop(context);
            },
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  Widget _contactOption(IconData icon, String title, Color color, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
          child: Row(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(width: 20),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
//=====================
//   MAIN PAGE
//=====================
class HomeNewPage extends StatefulWidget {
  const HomeNewPage({super.key});

  @override
  State<HomeNewPage> createState() => _HomeNewPageState();
}

class _HomeNewPageState extends State<HomeNewPage> {
  String? _activeMegaMenu;
  Timer? _menuCloseTimer;

  void _openMegaMenu(String menuName) {
    _menuCloseTimer?.cancel();
    if (_activeMegaMenu != menuName) {
      setState(() {
        _activeMegaMenu = menuName;
      });
    }
  }

  void _scheduleCloseMegaMenu() {
    _menuCloseTimer?.cancel();
    _menuCloseTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _activeMegaMenu = null;
      });
    });
  }

  void _cancelCloseMegaMenu() {
    _menuCloseTimer?.cancel();
  }

  void _toggleMegaMenu(String title) {
    setState(() {
      _activeMegaMenu = (_activeMegaMenu == title) ? null : title;
    });
  }

  @override
  void dispose() {
    _menuCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 800;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(95),
        child: HomeTopMenuBar(
          isMobile: isMobile,
          activeMegaMenu: _activeMegaMenu,
          onBack: () => Navigator.pop(context),
          onHomeTap: () {
            setState(() => _activeMegaMenu = null);
            Navigator.pop(context);
          },
          onMenuHoverEnter: _openMegaMenu,
          onMenuHoverExit: _scheduleCloseMegaMenu,
          onMenuToggle: _toggleMegaMenu,
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                HomeWelcomeSection(
                  onBackToPortfolio: () => Navigator.pop(context),
                ),
                HomeDarkFooterSection(isMobile: isMobile),
              ],
            ),
          ),
          if (_activeMegaMenu != null && !isMobile)
            HomeMegaMenuOverlay(
              screenWidth: screenWidth,
              activeMenu: _activeMegaMenu!,
              onMouseEnter: _cancelCloseMegaMenu,
              onMouseExit: _scheduleCloseMegaMenu,
              onCloseMenu: () => setState(() => _activeMegaMenu = null),
            ),
          LiveChatModule(
            screenWidth: screenWidth,
            isMobile: isMobile,
          ),
        ],
      ),
    );
  }
}
class HomeTopMenuBar extends StatelessWidget {
  final bool isMobile;
  final String? activeMegaMenu;
  final VoidCallback onBack;
  final VoidCallback onHomeTap;
  final ValueChanged<String> onMenuHoverEnter;
  final VoidCallback onMenuHoverExit;
  final ValueChanged<String> onMenuToggle;

  const HomeTopMenuBar({
    super.key,
    required this.isMobile,
    required this.activeMegaMenu,
    required this.onBack,
    required this.onHomeTap,
    required this.onMenuHoverEnter,
    required this.onMenuHoverExit,
    required this.onMenuToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF000080),
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 20 : 60,
        vertical: 22,
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              tooltip: "Back to Portfolio",
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 12),
            const Text(
              "ARIFUL'S PORTFOLIO",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 24,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            if (!isMobile) ...[
              _topMenuButton("Home", onHomeTap),
              _hoverMenuButton("Products"),
              _hoverMenuButton("Solutions"),
              _hoverMenuButton("Resources"),
            ] else
              PopupMenuButton<String>(
                icon: const Icon(Icons.menu, color: Colors.white, size: 30),
                onSelected: (String value) {
                  if (value == "Home") onHomeTap();
                },
                itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: "Home", child: Text("Home")),
                  PopupMenuItem<String>(value: "Products", child: Text("Products")),
                  PopupMenuItem<String>(value: "Solutions", child: Text("Solutions")),
                  PopupMenuItem<String>(value: "Resources", child: Text("Resources")),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _topMenuButton(String title, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        child: Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _hoverMenuButton(String title) {
    final bool isActive = activeMegaMenu == title;
    return MouseRegion(
      onEnter: (_) => onMenuHoverEnter(title),
      onExit: (_) => onMenuHoverExit(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: TextButton(
          onPressed: () => onMenuToggle(title),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Icon(
                isActive ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeMegaMenuOverlay extends StatelessWidget {
  final double screenWidth;
  final String activeMenu;
  final VoidCallback onMouseEnter;
  final VoidCallback onMouseExit;
  final VoidCallback onCloseMenu;

  const HomeMegaMenuOverlay({
    super.key,
    required this.screenWidth,
    required this.activeMenu,
    required this.onMouseEnter,
    required this.onMouseExit,
    required this.onCloseMenu,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: Center(
        child: MouseRegion(
          onEnter: (_) => onMouseEnter(),
          onExit: (_) => onMouseExit(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: screenWidth > 1180 ? 1100 : screenWidth * 0.94,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0A0A),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade800),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: activeMenu == "Products"
                ? ProductsMegaMenuContent(onItemTap: onCloseMenu)
                : activeMenu == "Solutions"
                ? SolutionsMegaMenuContent(onItemTap: onCloseMenu)
                : ResourcesMegaMenuContent(onItemTap: onCloseMenu),
          ),
        ),
      ),
    );
  }
}

// 3A. PRODUCTS POPUP CLASS
class ProductsMegaMenuContent extends StatelessWidget {
  final VoidCallback onItemTap;

  const ProductsMegaMenuContent({super.key, required this.onItemTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MegaMenuHeading("WEBSITE"),
              MegaMenuLink("Websites", onTap: onItemTap),
              MegaMenuLink("Website Templates", onTap: onItemTap),
              MegaMenuLink("AI Website Builder", onTap: onItemTap),
              MegaMenuLink("Design Intelligence", onTap: onItemTap),
              MegaMenuLink("Ecommerce", onTap: onItemTap),
              MegaMenuLink("Portfolios", onTap: onItemTap),
              MegaMenuLink("Blogs", onTap: onItemTap),
              MegaMenuLink("Analytics", onTap: onItemTap),
              const SizedBox(height: 18),
              InkWell(
                onTap: onItemTap,
                child: const Text(
                  "View All Features",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MegaMenuHeading("BUSINESS"),
              MegaMenuLink("Services", onTap: onItemTap),
              MegaMenuLink("Online Stores", onTap: onItemTap),
              MegaMenuLink("Invoicing", onTap: onItemTap),
              MegaMenuLink("Scheduling", onTap: onItemTap),
              MegaMenuLink("Limited Releases", onTap: onItemTap),
              MegaMenuLink("Content & Memberships", onTap: onItemTap),
              MegaMenuLink("Donations", onTap: onItemTap),
              MegaMenuLink("Financial Solutions", onTap: onItemTap),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MegaMenuHeading("MARKETING"),
              MegaMenuLink("Marketing Tools", onTap: onItemTap),
              MegaMenuLink("Email Campaigns", onTap: onItemTap),
              MegaMenuLink("SMS Campaigns", onTap: onItemTap),
              MegaMenuLink("SEO Tools", onTap: onItemTap),
              MegaMenuLink("AI Visibility", onTap: onItemTap),
              MegaMenuLink("Free Tools", onTap: onItemTap),
              const SizedBox(height: 20),
              const MegaMenuHeading("BUSINESS TOOLS"),
              MegaMenuLink("Domain Search", onTap: onItemTap),
              MegaMenuLink("Domain Transfer", onTap: onItemTap),
              MegaMenuLink("Business Email", onTap: onItemTap),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MegaMenuCard(
                title: "Build with AI",
                subtitle: "Create a personalized website with ease",
                icon: Icons.auto_awesome,
                onTap: onItemTap,
              ),
              const SizedBox(height: 14),
              MegaMenuCard(
                title: "Portfolio for Pros",
                subtitle: "Powerful enough for pros, easy enough for clients",
                icon: Icons.workspace_premium_outlined,
                onTap: onItemTap,
              ),
              const SizedBox(height: 14),
              MegaMenuCard(
                title: "Developer Circle",
                subtitle: "Our partner program for freelancers and agencies",
                icon: Icons.groups_outlined,
                onTap: onItemTap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 3B. SOLUTIONS POPUP CLASS
class SolutionsMegaMenuContent extends StatefulWidget {
  final VoidCallback onItemTap;

  const SolutionsMegaMenuContent({super.key, required this.onItemTap});

  @override
  State<SolutionsMegaMenuContent> createState() => _SolutionsMegaMenuContentState();
}

class _SolutionsMegaMenuContentState extends State<SolutionsMegaMenuContent> {
  String _selectedCategory = "Sports & Fitness";

  static const _categories = [
    "Creative Services",
    "Professional Services",
    "Education & Training",
    "Beauty",
    "Sports & Fitness",
    "Health & Wellness",
    "Home Services",
    "Events & Experiences",
    "Charities & Nonprofits",
    "Personal",
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MegaMenuHeading("SOLUTIONS FOR"),
              ..._categories.map((String cat) {
                final bool selected = _selectedCategory == cat;
                return MouseRegion(
                  onEnter: (_) => setState(() => _selectedCategory = cat),
                  child: InkWell(
                    onTap: widget.onItemTap,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        cat,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.grey.shade400,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        Container(
          width: 1,
          height: 310,
          color: Colors.grey.shade800,
          margin: const EdgeInsets.symmetric(horizontal: 24),
        ),
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MegaMenuHeading("EXPLORE"),
              Row(
                children: [
                  Text(
                    _selectedCategory,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                "Keep your workflow streamlined and your clients engaged, all on a single platform to grow your business.",
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _solutionTag("Custom Apps"),
                  _solutionTag("Client Portals"),
                  _solutionTag("Booking System"),
                  _solutionTag("Admin Dashboard"),
                  _solutionTag("Cloud Hosting"),
                  _solutionTag("Automation"),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _solutionTag(String label) {
    return InkWell(
      onTap: widget.onItemTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade700),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
        ),
      ),
    );
  }
}

// 3C. RESOURCES POPUP CLASS
class ResourcesMegaMenuContent extends StatelessWidget {
  final VoidCallback onItemTap;

  const ResourcesMegaMenuContent({super.key, required this.onItemTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MegaMenuHeading("24/7 SUPPORT"),
              MegaMenuRichItem(
                title: "Help Center",
                description:
                "In-depth guides and videos about the platform, our services, and how to get started.",
                onTap: onItemTap,
              ),
              const SizedBox(height: 18),
              MegaMenuRichItem(
                title: "Forum",
                description:
                "An online community for users to discuss best practices and seek advice.",
                onTap: onItemTap,
              ),
              const SizedBox(height: 18),
              MegaMenuRichItem(
                title: "Webinars",
                description:
                "Free online sessions where you will learn the basics and refine your skills.",
                onTap: onItemTap,
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 26),
              MegaMenuRichItem(
                title: "Blog",
                description:
                "Stories and solutions for the modern entrepreneur and developer.",
                onTap: onItemTap,
              ),
              const SizedBox(height: 18),
              MegaMenuRichItem(
                title: "Hire an Expert",
                description:
                "Let us do the work of finding you the perfect expert to help you stand out online.",
                onTap: onItemTap,
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const MegaMenuHeading("GET INSPIRED"),
              InkWell(
                onTap: onItemTap,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181818),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade800),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.collections_bookmark_outlined,
                          color: Colors.white, size: 32),
                      SizedBox(height: 14),
                      Text(
                        "Made with Flutter & Cloud",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        "A collection of inspirational applications and websites built for real businesses.",
                        style: TextStyle(
                            color: Colors.white70, fontSize: 12.5, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 3D. SHARED HELPER WIDGETS FOR MEGA MENU
class MegaMenuHeading extends StatelessWidget {
  final String title;
  const MegaMenuHeading(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class MegaMenuLink extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const MegaMenuLink(this.text, {super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class MegaMenuCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const MegaMenuCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade800),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MegaMenuRichItem extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback onTap;

  const MegaMenuRichItem({
    super.key,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class HomeWelcomeSection extends StatelessWidget {
  final VoidCallback onBackToPortfolio;

  const HomeWelcomeSection({super.key, required this.onBackToPortfolio});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 450),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.home_work_rounded,
            size: 80,
            color: Color(0xFF000080),
          ),
          const SizedBox(height: 20),
          const Text(
            "Welcome to the New Home Page",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF000080),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "Explore our latest digital solutions, custom software services, and enterprise applications.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF000080),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            onPressed: onBackToPortfolio,
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
            label: const Text(
              "Back to Portfolio",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class LiveChatModule extends StatefulWidget {
  final double screenWidth;
  final bool isMobile;

  const LiveChatModule({
    super.key,
    required this.screenWidth,
    required this.isMobile,
  });

  @override
  State<LiveChatModule> createState() => _LiveChatModuleState();
}

class _LiveChatModuleState extends State<LiveChatModule> {
  bool _isChatOpen = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  final _messages = [
    {
      "text": "Hello! I am Ariful's Assistant. How can I help you today?",
      "isUser": false,
      "time": "Just now",
    }
  ];

  String _generateSmartReply(String userText) {
    final String msg = userText.toLowerCase();

    if (msg.contains("hi") || msg.contains("hello") || msg.contains("hey")) {
      return "Hello! Welcome to Ariful's Portfolio. Are you looking for a Mobile App, Website, or Custom Software?";
    } else if (msg.contains("price") ||
        msg.contains("cost") ||
        msg.contains("charge") ||
        msg.contains("budget")) {
      return "Project pricing depends on features and complexity. Please share your requirements or contact via WhatsApp/Email for a quick quote!";
    } else if (msg.contains("app") ||
        msg.contains("flutter") ||
        msg.contains("android") ||
        msg.contains("ios")) {
      return "I specialize in cross-platform Flutter apps for Android, iOS, and Web with Firebase & REST API integration.";
    } else if (msg.contains("web") || msg.contains("website")) {
      return "I build fast, responsive web applications and business portals with custom admin panels.";
    } else if (msg.contains("contact") ||
        msg.contains("phone") ||
        msg.contains("whatsapp") ||
        msg.contains("email")) {
      return "You can reach me directly from the 'Contact Now' button on the main page via WhatsApp, Email, or LinkedIn.";
    } else if (msg.contains("help") ||
        msg.contains("support") ||
        msg.contains("service")) {
      return "Sure! I can help you with Full-Stack Development, Cross-Platform Apps, Logistics Automation, and Admin Dashboards.";
    } else if (msg.contains("thank")) {
      return "You're very welcome! Let me know if you have any other questions.";
    } else {
      return "Got it! I have noted your message: \"$userText\". Ariful will review this and reply shortly.";
    }
  }

  void _sendMessage() {
    final String text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({
        "text": text,
        "isUser": true,
        "time": "Now",
      });
      _chatController.clear();
    });

    _scrollToBottom();

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final String reply = _generateSmartReply(text);
      setState(() {
        _messages.add({
          "text": reply,
          "isUser": false,
          "time": "Now",
        });
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 25,
      bottom: 25,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isChatOpen)
            Container(
              width: widget.isMobile ? widget.screenWidth * 0.88 : 350,
              height: 430,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade300),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: const BoxDecoration(
                      color: Color(0xFF000080),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(17),
                        topRight: Radius.circular(17),
                      ),
                    ),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            const CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.white,
                              child: Icon(Icons.support_agent, color: Color(0xFF000080)),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF000080),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Live Support Chat",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                "Online - Replies within 1 min",
                                style: TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _isChatOpen = false),
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: const Color(0xFFF6F8FC),
                      child: ListView.builder(
                        controller: _chatScrollController,
                        padding: const EdgeInsets.all(14),
                        itemCount: _messages.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Map<String, dynamic> msg = _messages[index];
                          final bool isUser = msg["isUser"] == true;
                          final String messageText = msg["text"]?.toString() ?? "";

                          return Align(
                            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              constraints: const BoxConstraints(maxWidth: 240),
                              decoration: BoxDecoration(
                                color: isUser ? const Color(0xFF000080) : Colors.white,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(14),
                                  topRight: const Radius.circular(14),
                                  bottomLeft: Radius.circular(isUser ? 14 : 2),
                                  bottomRight: Radius.circular(isUser ? 2 : 14),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                messageText,
                                style: TextStyle(
                                  color: isUser ? Colors.white : Colors.black87,
                                  fontSize: 13.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Colors.grey.shade200)),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(17),
                        bottomRight: Radius.circular(17),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            onSubmitted: (_) => _sendMessage(),
                            decoration: const InputDecoration(
                              hintText: "Write a message...",
                              hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 10),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _sendMessage,
                          icon: const Icon(Icons.send_rounded, color: Color(0xFF000080)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _isChatOpen = !_isChatOpen),
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF000080),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white24, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isChatOpen
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chat_bubble_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isChatOpen ? "Close Chat" : "Live Chat",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeDarkFooterSection extends StatelessWidget {
  final bool isMobile;

  const HomeDarkFooterSection({super.key, required this.isMobile});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Colors.black,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 60,
        vertical: 60,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isMobile
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBrandColumn(),
              const SizedBox(height: 40),
              _buildFooterColumnsWrap(),
            ],
          )
              : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildBrandColumn()),
              const SizedBox(width: 40),
              Expanded(
                flex: 7,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _col1Products()),
                    Expanded(child: _col2SolutionsAndResources()),
                    Expanded(child: _col3FromAndSupport()),
                    Expanded(child: _col4CompanyAndFollow()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 50),
          Divider(color: Colors.grey.shade800, thickness: 1),
          const SizedBox(height: 25),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.language, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text("English", style: TextStyle(color: Colors.white, fontSize: 13)),
                  Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
                  SizedBox(width: 16),
                  Text("\$ SGD", style: TextStyle(color: Colors.white, fontSize: 13)),
                  Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
                ],
              ),
              Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  _footerBottomLink("Terms"),
                  _footerBottomLink("Privacy"),
                  _footerBottomLink("Security Measures"),
                  _footerBottomLink("Sitemap"),
                  Text(
                    "© 2003–2026 Ariful's Portfolio, Inc.",
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrandColumn() {
    return SizedBox(
      height: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.all_inclusive, color: Colors.white, size: 32),
              SizedBox(height: 18),
              Text(
                "A website makes it real",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white54),
                ),
                child: const Icon(Icons.verified_outlined, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  "Verified Full-Stack &\nCross-Platform Developer.",
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooterColumnsWrap() {
    return Wrap(
      spacing: 30,
      runSpacing: 30,
      children: [
        SizedBox(width: 160, child: _col1Products()),
        SizedBox(width: 160, child: _col2SolutionsAndResources()),
        SizedBox(width: 160, child: _col3FromAndSupport()),
        SizedBox(width: 160, child: _col4CompanyAndFollow()),
      ],
    );
  }

  Widget _col1Products() {
    return _footerSection("Products", const [
      "Website Templates",
      "Websites",
      "Domains",
      "AI Website Builder",
      "Design Intelligence",
      "Online Stores",
      "Services",
      "Invoicing",
      "Scheduling",
      "Content & Memberships",
      "Donations",
      "Payments",
      "Marketing Tools",
      "Professional Email",
      "Feature List",
      "Product Updates",
      "Pricing",
    ]);
  }

  Widget _col2SolutionsAndResources() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _footerSection("Solutions", const [
          "Creative Services",
          "Professional Services",
          "Education & Training",
          "Beauty",
          "Sports & Fitness",
          "Health & Wellness",
          "Home Services",
          "Events & Experiences",
          "Charities & Nonprofits",
          "Personal",
        ]),
        const SizedBox(height: 28),
        _footerSection("Resources", const [
          "Customer Examples",
          "Portfolio Collection",
          "Extensions",
          "Tech Blog",
          "Free Tools",
          "Business Name Generator",
          "Logo Maker",
        ]),
      ],
    );
  }

  Widget _col3FromAndSupport() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _footerSection("From Platform", const [
          "Acuity Scheduling",
          "Bio Sites",
          "Unfold",
          "Email Campaigns",
          "Apps for Pros",
        ]),
        const SizedBox(height: 28),
        _footerSection("Programs", const [
          "Circle",
          "Affiliates",
          "Students",
        ]),
        const SizedBox(height: 28),
        _footerSection("Support", const [
          "Help Center",
          "Forum",
          "Webinars",
          "Hire an Expert",
          "Developer Blog",
          "Developer Platform",
          "System Status",
        ]),
      ],
    );
  }

  Widget _col4CompanyAndFollow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _footerSection("Company", const [
          "About",
          "Careers",
          "Our Brand",
          "Accessibility",
          "Newsroom",
          "Press & Media",
          "Contact Us",
        ]),
        const SizedBox(height: 28),
        _footerSection("Follow", const [
          "Instagram",
          "YouTube",
          "LinkedIn",
          "Facebook",
          "X",
        ]),
      ],
    );
  }

  Widget _footerSection(String heading, Iterable<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 14),
        ...items.map(
              (String item) => Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: InkWell(
              onTap: () {},
              child: Text(
                item,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _footerBottomLink(String text) {
    return InkWell(
      onTap: () {},
      child: Text(
        text,
        style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
      ),
    );
  }
}
// --- Personal Details Panel Section ---
class PersonalDetailsPage extends StatelessWidget {
  final String currentName;
  final String currentMail;
  final String currentPhone;
  final String currentLinkedin;
  final String currentColam4;
  final String currentColam5;
  final String currentColam6;
  final String currentAboutMe;
  final String currentOpDomain;
  final String currentTechnicalStack;
  final String currentAboutMeTitle;
  final String currentOperationalDomainTitle;
  final String currentTechnicalStackTitle;
  final String currentHomeMenuTitle;
  final String currentResumeMenuTitle;
  final String currentProjectMenuTitle;
  final String currentExperienceMenuTitle;
  final String currentExpertiseMenuTitle;

  final List<ExperienceData> currentExperiences;
  final List<ProjectData> currentProjects;
  final String currentPdfName;
  final List<ExpertiseSectionData> currentExpertise;
  final Function(List<ExpertiseSectionData>) onExpertiseUpdated;

  final Function(String) onNameUpdated;
  final Function(Uint8List) onImageUpdated;
  final Function(String) onMailUpdated;
  final Function(String) onPhoneUpdated;
  final Function(String) onLinkedinUpdated;
  final Function(String) onColam4Updated;
  final Function(String) onColam5Updated;
  final Function(String) onColam6Updated;
  final Function(String) onAboutMeUpdated;
  final Function(String) onOpDomainUpdated;
  final Function(String) onTechnicalStackUpdated;
  final Function(String) onAboutMeTitleUpdated;
  final Function(String) onOperationalDomainTitleUpdated;
  final Function(String) onTechnicalStackTitleUpdated;
  final Function(String) onHomeMenuTitleUpdated;
  final Function(String) onResumeMenuTitleUpdated;
  final Function(String) onProjectMenuTitleUpdated;
  final Function(String) onExperienceMenuTitleUpdated;
  final Function(String) onExpertiseMenuTitleUpdated;
  final Function(List<ExperienceData>) onExperiencesUpdated;
  final Function(List<ProjectData>) onProjectsUpdated;


  final Function(Uint8List, String) onPdfUploaded;

  const PersonalDetailsPage({
    super.key,
    required this.currentName,
    required this.currentMail,
    required this.currentPhone,
    required this.currentLinkedin,
    required this.currentColam4,
    required this.currentColam5,
    required this.currentColam6,
    required this.currentAboutMe,
    required this.currentOpDomain,
    required this.currentTechnicalStack,
    required this.currentExperiences,
    required this.currentAboutMeTitle,
    required this.currentOperationalDomainTitle,
    required this.currentTechnicalStackTitle,
    required this.currentHomeMenuTitle,
    required this.currentResumeMenuTitle,
    required this.currentProjectMenuTitle,
    required this.currentExperienceMenuTitle,
    required this.currentExpertiseMenuTitle,
    required this.currentProjects,
    required this.currentPdfName,
    required this.currentExpertise,
    required this.onExpertiseUpdated,
    required this.onNameUpdated,
    required this.onImageUpdated,
    required this.onMailUpdated,
    required this.onPhoneUpdated,
    required this.onLinkedinUpdated,
    required this.onColam4Updated,
    required this.onColam5Updated,
    required this.onColam6Updated,
    required this.onAboutMeUpdated,
    required this.onOpDomainUpdated,
    required this.onTechnicalStackUpdated,
    required this.onAboutMeTitleUpdated,
    required this.onOperationalDomainTitleUpdated,
    required this.onTechnicalStackTitleUpdated,
    required this.onHomeMenuTitleUpdated,
    required this.onResumeMenuTitleUpdated,
    required this.onProjectMenuTitleUpdated,
    required this.onExperienceMenuTitleUpdated,
    required this.onExpertiseMenuTitleUpdated,
    required this.onExperiencesUpdated,
    required this.onProjectsUpdated,
    required this.onPdfUploaded,
  });

  void _pickPdfFile(BuildContext context) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.bytes != null) {
      Uint8List fileBytes = result.files.single.bytes!;
      String fileName = result.files.single.name;
      String? downloadUrl = await uploadResumeToStorage(fileBytes, fileName);

      if (downloadUrl != null) {
        await FirebaseFirestore.instance.collection('my_portfolio').doc('user_data').set({
          'resumeUrl': downloadUrl,
          'resumeName': fileName,
        }, SetOptions(merge: true));

        onPdfUploaded(fileBytes, fileName);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$fileName saved to cloud!'), backgroundColor: Colors.green),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file selected!')),
      );
    }
  }

  void _showContactEditDialog(BuildContext context, String title, String hint, String currentValue, Function(String) onSave) {
    TextEditingController controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(controller: controller, maxLines: null, decoration: InputDecoration(hintText: hint)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                onSave(controller.text);
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }
  void _showWhatsAppEditDialog(
      BuildContext context,
      String currentValue,
      Function(String) onSave,
      ) {
    final TextEditingController phoneController =
    TextEditingController(
      text: currentValue.replaceFirst(
        RegExp(r'^\+65'),
        '',
      ),
    );

    String dialCode = '+65';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Edit WhatsApp Number"),
          content: SizedBox(
            width: 320,
            child: IntlPhoneField(
              controller: phoneController,
              initialCountryCode: 'SG',
              decoration: const InputDecoration(
                labelText: "WhatsApp Number",
                hintText: "Enter phone number",
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              disableLengthCheck: true,

              onCountryChanged: (country) {
                dialCode = '+${country.dialCode}';
              },

              onChanged: (phone) {
                dialCode = phone.countryCode;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),

            ElevatedButton(
              onPressed: () async {
                final localNumber = phoneController.text.replaceAll(
                  RegExp(r'[^0-9]'),
                  '',
                );

                if (localNumber.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Please enter WhatsApp number"),
                    ),
                  );
                  return;
                }

                final fullNumber = '$dialCode$localNumber';

                try {
                  await FirebaseFirestore.instance
                      .collection('my_portfolio')
                      .doc('user_data')
                      .set({
                    'phoneNumber': fullNumber,
                  }, SetOptions(merge: true));
                  // Home page variable update
                  onSave(fullNumber);

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          "WhatsApp number saved: $fullNumber",
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("Save failed: $e"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  void _showTitleEditDialog(
      BuildContext context,
      String dialogTitle,
      String currentTitle,
      Function(String) onSave,
      ) {
    final TextEditingController controller =
    TextEditingController(text: currentTitle);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: "Enter new title",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                onSave(controller.text.trim());
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  void _showNameEditDialog(BuildContext context) {
    TextEditingController nameController = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit Profile Name"),
          content: TextField(controller: nameController, decoration: const InputDecoration(hintText: "Enter your name")),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () {
                onNameUpdated(nameController.text);
                Navigator.pop(context);
              },
              child: const Text("Save"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickDashboardImage(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile =
    await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final Uint8List imageBytes =
      await pickedFile.readAsBytes();

      onImageUpdated(imageBytes);
      String imageUrl =
      await uploadDashboardImage(imageBytes);
      await FirebaseFirestore.instance
          .collection("my_portfolio")
          .doc("user_data")
          .set({
        "dashboardImage": imageUrl,
      }, SetOptions(merge: true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Dashboard Photo uploaded successfully!"),
          ),
        );
      }
    }
  }
  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Change Admin Password"),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Current Password",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "New Password",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: "Confirm New Password",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final currentPassword =
                currentPasswordController.text.trim();
                final newPassword =
                newPasswordController.text.trim();
                final confirmPassword =
                confirmPasswordController.text.trim();

                if (currentPassword.isEmpty ||
                    newPassword.isEmpty ||
                    confirmPassword.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("complete all the fields!"),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (newPassword.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "New password must be at least 6 characters!",
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (newPassword != confirmPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "New password and Confirm password can't matching!",
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  final User? user =
                      FirebaseAuth.instance.currentUser;

                  if (user == null || user.email == null) {
                    throw FirebaseAuthException(
                      code: "user-not-found",
                    );
                  }

                  final credential =
                  EmailAuthProvider.credential(
                    email: user.email!,
                    password: currentPassword,
                  );

                  await user.reauthenticateWithCredential(
                    credential,
                  );

                  await user.updatePassword(newPassword);

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Password update successful!",
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } on FirebaseAuthException catch (e) {
                  String message =
                      "Password update successful!";

                  if (e.code == "wrong-password" ||
                      e.code == "invalid-credential") {
                    message = "Current Password worng!";
                  }

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text("Change Password"),
            ),
          ],
        );
      },
    );
  }
  Future<void> _pickAndUploadFavicon(
      BuildContext context,
      ) async {
    try {
      final FilePickerResult? result =
      await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'png',
          'jpg',
          'jpeg',
        ],
        allowMultiple: false,
        withData: true,
      );
      if (result == null) {
        return;
      }
      final PlatformFile selectedFile =
          result.files.single;
      final Uint8List? imageBytes =
          selectedFile.bytes;
      if (imageBytes == null) {
        throw Exception("Image data not found!");
      }
      if (selectedFile.size > 2 * 1024 * 1024) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Icon image must be below 2MB!",
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final String extension =
          selectedFile.extension?.toLowerCase() ?? 'png';

      final String faviconUrl = await uploadToCloudinary(
        imageBytes,
        "favicon_${DateTime.now().millisecondsSinceEpoch}.$extension",
        folder: "portfolio/favicon",
      );

      if (faviconUrl.isEmpty) {
        throw Exception("Cloudinary upload failed!");
      }

      await FirebaseFirestore.instance
          .collection('my_portfolio')
          .doc('user_data')
          .set({
        'faviconUrl': faviconUrl,
      }, SetOptions(merge: true));

      updateBrowserFavicon(faviconUrl);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Website tab icon update successfully!",
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Icon can't update: $e",
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF000080),
        title: const Text(
          "ADD PERSONAL DETAILS",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: screenWidth > 800
            ? Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildLeftFormColumn(context)),
            const SizedBox(width: 30),
            Expanded(child: _buildRightFormColumn(context)),
          ],
        )
            : Column(
          children: [
            _buildLeftFormColumn(context),
            _buildRightFormColumn(context),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftFormColumn(BuildContext context) {
    return Column(children: [
      _premiumRow(context, "1", currentPdfName.isNotEmpty ? "Resume: $currentPdfName" : "Resume (No file selected)", "Select PDF CV", () => _pickPdfFile(context)),
      _premiumRow(context, "2", "Profile name", "Add Profile name", () {
        _showNameEditDialog(context);
      }),
      _premiumThreeRow(
        context,
        "3",
        "Mail",
            () => _showContactEditDialog(context, "Edit Mail Address", "example@mail.com", currentMail, onMailUpdated),
        "Phone",
            () => _showWhatsAppEditDialog(
          context,
          currentPhone,
          onPhoneUpdated,
        ),
        "Linkedin",
            () => _showContactEditDialog(context, "Edit LinkedIn Link", "linkedin.com/in/username", currentLinkedin, onLinkedinUpdated),
      ),
      _premiumRow(context, "4", "Colam-4", "Add Description", () {
        _showContactEditDialog(context, "Edit Colam-4 Text", "Enter text for hero top section", currentColam4, onColam4Updated);
      }),
      _premiumRow(context, "5", "Colam-5", "Add Description", () {
        _showContactEditDialog(context, "Edit Colam-5 Text", "Enter bold main text", currentColam5, onColam5Updated);
      }),
      _premiumRow(context, "6", "Colam-6", "Add Description", () {
        _showContactEditDialog(context, "Edit Colam-6 Text", "Enter hero description subtext", currentColam6, onColam6Updated);
      }),
      _premiumRow(context, "7", currentAboutMeTitle, "Add Description", () {
        _showContactEditDialog(
          context,
          "Edit About Me Text",
          "Enter details for About Me footer section",
          currentAboutMe,
          onAboutMeUpdated,
        );
      }),

// 👇 Row
      _premiumRow(
        context,
        "7A",
        "About Me Title",
        "Edit Title",
            () {
          _showTitleEditDialog(
            context,
            "Edit About Me Title",
            currentAboutMeTitle,
            onAboutMeTitleUpdated,
          );
        },
      ),

// Premium Administrator Password Card
      _adminPasswordCard(context),
      _premiumRow(
        context,
        "7C",
        "Website Tab Icon",
        "Change Icon",
            () {
          _pickAndUploadFavicon(context);
        },
      ),

    ]);
  }

  Widget _buildRightFormColumn(BuildContext context) {
    return Column(children: [
      _premiumRow(context, "8", currentOperationalDomainTitle, "Add Description", () {
        _showContactEditDialog(
          context,
          "Edit Operational Domain Text",
          "Enter text for Operational Domain footer section",
          currentOpDomain,
          onOpDomainUpdated,
        );
      }),
      _premiumRow(
        context,
        "8A",
        "Operational Domain Title",
        "Edit Title",
            () {
          _showTitleEditDialog(
            context,
            "Edit Operational Domain Title",
            currentOperationalDomainTitle,
            onOperationalDomainTitleUpdated,
          );
        },
      ),
      _premiumRow(context, "9", "Dashboard Photo", "Add Dashboard Photo", () {
        _pickDashboardImage(context);
      }),
      _premiumRow(context, "10", "My Project", "Add My Project", () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProjectFormPage(
              initialProjects: currentProjects,
              onSave: onProjectsUpdated,
            ),
          ),
        );
      }),
      _premiumRow(context, "11", "Experience", "Add Experience", () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ExperienceFormPage(
              initialExperiences: currentExperiences,
              onSave: onExperiencesUpdated,
            ),
          ),
        );
      }),
           // (Expertise)
      _premiumRow(context, "12", "Expertise", "Add Experience", () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ExpertiseFormPage(
              initialSections: currentExpertise,
              onSave: (updatedSections) {
                onExpertiseUpdated(updatedSections);
              },
            ),
          ),
        );
      }),
      _premiumRow(context, "13", currentTechnicalStackTitle, "Add Description", () {
        _showContactEditDialog(
          context,
          "Edit Technical Stack",
          "Flutter, Dart, Firebase, REST APIs, GitHub",
          currentTechnicalStack,
          onTechnicalStackUpdated,
        );
      }),
      _premiumRow(
        context,
        "13A",
        "Technical Stack Title",
        "Edit Title",
            () {
          _showTitleEditDialog(
            context,
            "Edit Technical Stack Title",
            currentTechnicalStackTitle,
            onTechnicalStackTitleUpdated,
          );
        },
      ),
      _premiumRow(
        context,
        "15",
        "Home Menu Title",
        "Edit Title",
            () {
          _showTitleEditDialog(
            context,
            "Edit Home Menu Title",
            currentHomeMenuTitle,
            onHomeMenuTitleUpdated,
          );
        },
      ),

      _premiumRow(
        context,
        "16",
        "Resume/CV Menu Title",
        "Edit Title",
            () {
          _showTitleEditDialog(
            context,
            "Edit Resume/CV Menu Title",
            currentResumeMenuTitle,
            onResumeMenuTitleUpdated,
          );
        },
      ),

      _premiumRow(
        context,
        "17",
        "My Project Menu Title",
        "Edit Title",
            () {
          _showTitleEditDialog(
            context,
            "Edit My Project Menu Title",
            currentProjectMenuTitle,
            onProjectMenuTitleUpdated,
          );
        },
      ),

      _premiumRow(
        context,
        "18",
        "Experience Menu Title",
        "Edit Title",
            () {
          _showTitleEditDialog(
            context,
            "Edit Experience Menu Title",
            currentExperienceMenuTitle,
            onExperienceMenuTitleUpdated,
          );
        },
      ),

      _premiumRow(
        context,
        "19",
        "Expertise Menu Title",
        "Edit Title",
            () {
          _showTitleEditDialog(
            context,
            "Edit Expertise Menu Title",
            currentExpertiseMenuTitle,
            onExpertiseMenuTitleUpdated,
          );
        },
      ),
      _premiumRow(context, "14", "Additional", "Add Description", () {}),
    ]);
  }
  Widget _adminPasswordCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          const SizedBox(
            width: 30,
            child: Text(
              "7B",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF000080),
              ),
            ),
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF000080),
                    Color(0xFF162A72),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFFD700),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF000080).withOpacity(0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    _showChangePasswordDialog(context);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700)
                                .withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFFFD700),
                            ),
                          ),
                          child: const Icon(
                            Icons.admin_panel_settings,
                            color: Color(0xFFFFD700),
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 15),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                "ADMINISTRATOR SECURITY",
                                style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 1,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                "Change Admin Password",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                "Firebase protected admin access",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD700),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.lock_reset,
                                color: Color(0xFF000080),
                                size: 19,
                              ),
                              SizedBox(width: 5),
                              Text(
                                "CHANGE",
                                style: TextStyle(
                                  color: Color(0xFF000080),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumRow(BuildContext context, String no, String title, String action, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        children: [
          SizedBox(width: 30, child: Text(no, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF000080)))),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 5, offset: const Offset(0, 3))]),
              child: Row(children: [
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
                if (action.isNotEmpty) TextButton(onPressed: onTap, child: Text(action, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)))
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _premiumThreeRow(BuildContext context, String no, String t1, VoidCallback onTap1, String t2, VoidCallback onTap2, String t3, VoidCallback onTap3) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 30, child: Text(no, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF000080)))),
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [_subItem(t1, onTap1), _subItem(t2, onTap2), _subItem(t3, onTap3, isLast: true)]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subItem(String label, VoidCallback onTap, {bool isLast = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    decoration: BoxDecoration(border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey.shade200))),
    child: Row(children: [Expanded(child: Text(label, style: const TextStyle(fontSize: 15))), TextButton(onPressed: onTap, child: const Text("Add details", style: TextStyle(fontWeight: FontWeight.bold)))]),
  );
}

// --- Experience Management Section ---
class ExperienceFormPage extends StatefulWidget {
  final List<ExperienceData> initialExperiences;
  final Function(List<ExperienceData>) onSave;

  const ExperienceFormPage({super.key, required this.initialExperiences, required this.onSave});

  @override
  State<ExperienceFormPage> createState() => _ExperienceFormPageState();
}

class _ExperienceFormPageState extends State<ExperienceFormPage> {
  final List<ExperienceData> _tempExperiences = [];
  int _currentIndex = 0;

  late TextEditingController _companyController;
  late TextEditingController _dateController;
  late TextEditingController _designationController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    if (widget.initialExperiences.isNotEmpty) {
      for (var exp in widget.initialExperiences) {
        _tempExperiences.add(ExperienceData(
          companyName: exp.companyName,
          date: exp.date,
          designation: exp.designation,

          designations: exp.designations.map((item) {
            return DesignationData(
              title: item.title,
              fromDate: item.fromDate,
              toDate: item.toDate,
              serviceLength: item.serviceLength,
            );
          }).toList(),

          description: exp.description,
          certificates: List.from(exp.certificates),
        ));
      }
    } else {
      _tempExperiences.add(ExperienceData());
    }
    _initControllers();
  }

  void _initControllers() {
    final currentExp = _tempExperiences[_currentIndex];
    _companyController = TextEditingController(text: currentExp.companyName);
    _dateController = TextEditingController(text: currentExp.date);
    _designationController = TextEditingController(text: currentExp.designation);
    _descriptionController = TextEditingController(text: currentExp.description);
  }

  void _saveCurrentState() {
    final ExperienceData currentExperience =
    _tempExperiences[_currentIndex];

    currentExperience.companyName =
        _companyController.text.trim();

    currentExperience.date =
        _dateController.text.trim();

    currentExperience.description =
        _descriptionController.text.trim();
    currentExperience.designation =
    currentExperience.designations.isNotEmpty
        ? currentExperience.designations.first.title.trim()
        : '';
  }
  Future<void> _saveAllDataToFirestore() async {
    try {
      _saveCurrentState();

      final expData = await Future.wait(
        _tempExperiences.map((e) async {
          return {
            'companyName': e.companyName,
            'date': e.date,
            'designation': e.designations.isNotEmpty &&
                e.designations.first.title.trim().isNotEmpty
                ? e.designations.first.title.trim()
                : e.designation,

            'designations': e.designations.map((item) {
              return {
                'title': item.title.trim(),
                'fromDate': item.fromDate.trim(),
                'toDate': item.toDate.trim(),
                'serviceLength': item.serviceLength.trim(),
              };
            }).toList(),

            'description': e.description,

            'certificates': await Future.wait(
              e.certificates.map((c) async {
                String? imageUrl = c.imageUrl;
                if (c.bytes != null) {
                  imageUrl = await uploadFileToStorage(
                    c.bytes!,
                    c.name,
                  );
                }

                return {
                  'name': c.name,
                  'imageUrl': imageUrl,
                };
              }).toList(),
            ),
          };
        }).toList(),
      );

      await FirebaseFirestore.instance
          .collection('my_portfolio')
          .doc('user_data')
          .set({
        'experiences': expData,
      }, SetOptions(merge: true));

      debugPrint("Experience saved successfully.");
    } catch (e) {
      debugPrint("Experience save error: $e");
    }
  }

  Future<void> _pickCertificate() async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _tempExperiences[_currentIndex].certificates.add(
          CertificateData(name: file.name, bytes: bytes),
        );
      });
    }
  }


  @override
  void dispose() {
    _companyController.dispose();
    _dateController.dispose();
    _designationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
  Widget _buildDesignationSection() {
    final ExperienceData currentExperience =
    _tempExperiences[_currentIndex];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF4A90E2),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.workspace_premium,
                color: Color(0xFF000080),
                size: 26,
              ),
              SizedBox(width: 10),
              Text(
                "Career Progression",
                style: TextStyle(
                  color: Color(0xFF000080),
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 6),

          const Text(
            "Add every designation and its service duration.",
            style: TextStyle(
              color: Colors.black54,
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 18),

          if (currentExperience.designations.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.grey.shade300,
                ),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.work_history_outlined,
                    size: 38,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 8),
                  Text(
                    "No designation added yet",
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          ...List.generate(
            currentExperience.designations.length,
                (index) {
              final DesignationData designation =
              currentExperience.designations[index];

              final String uniqueKey =
              identityHashCode(designation).toString();

              return Container(
                margin: const EdgeInsets.only(bottom: 15),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.grey.shade300,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor:
                          const Color(0xFF000080),
                          child: Text(
                            "${index + 1}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Text(
                            "Designation ${index + 1}",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF000080),
                            ),
                          ),
                        ),

                        IconButton(
                          tooltip: "Delete Designation",
                          onPressed: () {
                            setState(() {
                              currentExperience.designations
                                  .removeAt(index);
                            });
                          },
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    TextFormField(
                      key: ValueKey("${uniqueKey}_title"),
                      initialValue: designation.title,
                      onChanged: (value) {
                        designation.title = value;
                      },
                      decoration: _designationInputDecoration(
                        "Designation Title",
                        Icons.badge_outlined,
                      ),
                    ),

                    const SizedBox(height: 12),

                    LayoutBuilder(
                      builder: (context, constraints) {
                        final bool wideScreen =
                            constraints.maxWidth > 650;

                        final Widget fromDateField =
                        TextFormField(
                          key: ValueKey(
                            "${uniqueKey}_fromDate",
                          ),
                          initialValue: designation.fromDate,
                          onChanged: (value) {
                            designation.fromDate = value;
                          },
                          decoration:
                          _designationInputDecoration(
                            "From Date",
                            Icons.calendar_month_outlined,
                          ),
                        );

                        final Widget toDateField =
                        TextFormField(
                          key: ValueKey(
                            "${uniqueKey}_toDate",
                          ),
                          initialValue: designation.toDate,
                          onChanged: (value) {
                            designation.toDate = value;
                          },
                          decoration:
                          _designationInputDecoration(
                            "To Date",
                            Icons.event_available_outlined,
                          ),
                        );

                        final Widget serviceLengthField =
                        TextFormField(
                          key: ValueKey(
                            "${uniqueKey}_serviceLength",
                          ),
                          initialValue:
                          designation.serviceLength,
                          onChanged: (value) {
                            designation.serviceLength = value;
                          },
                          decoration:
                          _designationInputDecoration(
                            "Service Length",
                            Icons.timelapse_outlined,
                          ),
                        );

                        if (wideScreen) {
                          return Row(
                            children: [
                              Expanded(child: fromDateField),
                              const SizedBox(width: 12),
                              Expanded(child: toDateField),
                              const SizedBox(width: 12),
                              Expanded(
                                child: serviceLengthField,
                              ),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            fromDateField,
                            const SizedBox(height: 12),
                            toDateField,
                            const SizedBox(height: 12),
                            serviceLengthField,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 5),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  currentExperience.designations.add(
                    DesignationData(),
                  );
                });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF000080),
                side: const BorderSide(
                  color: Color(0xFF000080),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text(
                "Add Another Designation",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _designationInputDecoration(
      String label,
      IconData icon,
      ) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(
        icon,
        color: const Color(0xFF000080),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 17,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: Color(0xFF000080),
          width: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF000080),
        title: Text(
          "Experience Entry Box (${_currentIndex + 1}/${_tempExperiences.length})",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            width: screenWidth > 900 ? 900 : screenWidth * 0.95,
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInputField("Company name", _companyController),
                const SizedBox(height: 20),
                _buildInputField("Date", _dateController),
                const SizedBox(height: 20),
                _buildDesignationSection(),
                const SizedBox(height: 20),
                _buildInputField("Description:", _descriptionController, maxLines: 8),
                const SizedBox(height: 20),
                if (_tempExperiences[_currentIndex].certificates.isNotEmpty) ...[
                  const Text("Selected Certificates Preview:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 15,
                    runSpacing: 15,
                    children: _tempExperiences[_currentIndex].certificates.map((cert) {
                      return Stack(
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300, width: 1.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: cert.bytes != null
                                  ? Image.memory(
                                cert.bytes!,
                                fit: BoxFit.cover,
                              )
                                  : (cert.imageUrl?.trim().isNotEmpty ?? false)
                                  ? Image.network(
                                cert.imageUrl!,
                                fit: BoxFit.cover,
                                loadingBuilder: (
                                    context,
                                    child,
                                    loadingProgress,
                                    ) {
                                  if (loadingProgress == null) {
                                    return child;
                                  }

                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                },
                                errorBuilder: (
                                    context,
                                    error,
                                    stackTrace,
                                    ) {
                                  return const Icon(
                                    Icons.broken_image,
                                    size: 40,
                                    color: Colors.red,
                                  );
                                },
                              )
                                  : const Icon(
                                Icons.image_not_supported,
                                size: 40,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 4,
                            top: 4,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _tempExperiences[_currentIndex].certificates.remove(cert);
                                });
                              },
                              child: Container(
                                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                child: const Icon(Icons.cancel, color: Colors.red, size: 22),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
                screenWidth > 600
                    ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCertificateControls(),
                    const Spacer(),
                    _buildActionControls(),
                  ],
                )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCertificateControls(),
                    const SizedBox(height: 25),
                    _buildActionControls(),
                  ],
                ),
                if (_tempExperiences.length > 1) ...[
                  const SizedBox(height: 30),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.arrow_back),
                        label: const Text("Previous Block"),
                        onPressed: _currentIndex > 0
                            ? () {
                          _saveCurrentState();
                          setState(() {
                            _currentIndex--;
                            _initControllers();
                          });
                        }
                            : null,
                      ),
                      Text("Block ${_currentIndex + 1} of ${_tempExperiences.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text("Next Block"),
                        onPressed: _currentIndex < _tempExperiences.length - 1
                            ? () {
                          _saveCurrentState();
                          setState(() {
                            _currentIndex++;
                            _initControllers();
                          });
                        }
                            : null,
                      ),
                    ],
                  )
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCertificateControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBlueprintButton("Add Certificate", _pickCertificate),
        const SizedBox(height: 10),
        Container(
          width: 250,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF4A90E2), width: 1.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _tempExperiences[_currentIndex].certificates.isNotEmpty ? _tempExperiences[_currentIndex].certificates.last.name : "Certificate name",
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
        const SizedBox(height: 10),
        _buildBlueprintButton("Add more certificate", _pickCertificate),
      ],
    );
  }

  Widget _buildActionControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildBlueprintButton("Save Data", () async {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Uploading & saving experience data...'),
              duration: Duration(seconds: 2),
            ),
          );

          await _saveAllDataToFirestore();
          widget.onSave(_tempExperiences);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Experience data saved successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context);
          }
        }),

        const SizedBox(height: 10),

        _buildBlueprintButton("Delete Experience", () {
          if (_tempExperiences.length > 1) {
            setState(() {
              _tempExperiences.removeAt(_currentIndex);

              if (_currentIndex >= _tempExperiences.length) {
                _currentIndex = _tempExperiences.length - 1;
              }

              _initControllers();
            });
          }
        }),

        const SizedBox(height: 10),

        _buildBlueprintButton("Add more Experience", () {
          _saveCurrentState();

          setState(() {
            _tempExperiences.add(ExperienceData());
            _currentIndex = _tempExperiences.length - 1;
            _initControllers();
          });
        }),
      ],
    );
  }

  Widget _buildInputField(String hint, TextEditingController controller, {int maxLines = 1}) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        alignLabelWithHint: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF4A90E2), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFF000080), width: 2),
        ),
      ),
    );
  }

  Widget _buildBlueprintButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF4A90E2), width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

// --- Project Creator Form Page Section ---
class ProjectFormPage extends StatefulWidget {
  final List<ProjectData> initialProjects;
  final Function(List<ProjectData>) onSave;

  const ProjectFormPage({super.key, required this.initialProjects, required this.onSave});

  @override
  State<ProjectFormPage> createState() => _ProjectFormPageState();
}

class _ProjectFormPageState extends State<ProjectFormPage> {
  final List<ProjectData> _tempProjects = [];
  int _currentIndex = 0;

  late TextEditingController _nameController;
  late TextEditingController _titleController;
  late TextEditingController _challengesController;
  late TextEditingController _featuresController;
  late TextEditingController _stackController;

  @override
  void initState() {
    super.initState();

    if (widget.initialProjects.isNotEmpty) {
      for (var p in widget.initialProjects) {
        _tempProjects.add(
          ProjectData(
            projectName: p.projectName,
            title: p.title,
            challengesAndSolutions: p.challengesAndSolutions,
            keyFeatures: p.keyFeatures,
            githubUrl: p.githubUrl,
            codeSnippet: p.codeSnippet,
            mediaFiles: List<Uint8List>.from(p.mediaFiles),
            mediaUrls: List<String>.from(p.mediaUrls),
          ),
        );
      }
    } else {
      _tempProjects.add(ProjectData());
    }

    _initControllers();
  }
  void _initControllers() {
    final currentProj = _tempProjects[_currentIndex];
    _nameController = TextEditingController(text: currentProj.projectName);
    _titleController = TextEditingController(text: currentProj.title);
    _challengesController = TextEditingController(text: currentProj.challengesAndSolutions);
    _featuresController = TextEditingController(text: currentProj.keyFeatures);
    _stackController =
        TextEditingController(text: currentProj.stackDescription);
  }

  void _saveCurrentState() {
    _tempProjects[_currentIndex].projectName = _nameController.text;
    _tempProjects[_currentIndex].title = _titleController.text;
    _tempProjects[_currentIndex].challengesAndSolutions = _challengesController.text;
    _tempProjects[_currentIndex].keyFeatures = _featuresController.text;
    _tempProjects[_currentIndex].stackDescription =
        _stackController.text;
  }
  Future<void> _saveProjectsToFirestore() async {
    try {
      _saveCurrentState();

      final projectData = await Future.wait(
        _tempProjects.map((p) async {
          List<String> updatedUrls = List<String>.from(p.mediaUrls);

          for (var img in p.mediaFiles) {
            String url = await uploadFileToStorage(
              img,
              "project_${DateTime.now().millisecondsSinceEpoch}.png",
            );
            debugPrint("URL = $url");
            if (url.isNotEmpty) {
              updatedUrls.add(url);
            }
          }

          p.mediaUrls = updatedUrls;
          p.mediaFiles.clear();

          debugPrint("Uploaded URLs: $updatedUrls");

          return {
            'projectName': p.projectName,
            'title': p.title,
            'challengesAndSolutions': p.challengesAndSolutions,
            'keyFeatures': p.keyFeatures,
            'githubUrl': p.githubUrl,
            'codeSnippet': p.codeSnippet,
            'stackDescription': p.stackDescription,
            'mediaFiles': updatedUrls,
          };
        }).toList(),
      );

      await FirebaseFirestore.instance
          .collection('my_portfolio')
          .doc('user_data')
          .set({
        'projects': projectData,
      }, SetOptions(merge: true));

      debugPrint("Projects saved successfully.");
    } catch (e) {
      debugPrint("Project save error: $e");
    }
  }
  Future<void> _pickLiveDemoMedia() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> files = await picker.pickMultiImage();

    if (files.isEmpty) return;
    List<Uint8List> newImages = [];

    for (var file in files) {
      final bytes = await file.readAsBytes();
      newImages.add(bytes);
    }

    setState(() {
      _tempProjects[_currentIndex].mediaFiles.addAll(newImages);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "${newImages.length} image(s) added successfully.",
        ),
        backgroundColor: Colors.green,
      ),
    );
  }
  void _showCodeEditorDialog() {
    TextEditingController codeController = TextEditingController(text: _tempProjects[_currentIndex].codeSnippet);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Container(
          width: 800,
          height: 550,
          color: const Color(0xFF2B2B2B),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.terminal, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text("Apps Drescribtin Editor Panel", style: TextStyle(color: Colors.white, fontSize: 15, fontFamily: 'monospace')),
                ],
              ),
              const Divider(color: Colors.grey),
              Expanded(
                child: TextField(
                  controller: codeController,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: const TextStyle(color: Color(0xFFA9B7C6), fontFamily: 'monospace', fontSize: 14, height: 1.4),
                  decoration: const InputDecoration(
                    hintText: "// Paste or write your production ready code template here...",
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.white60))),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4B6EAF)),
                    onPressed: () {
                      _tempProjects[_currentIndex].codeSnippet = codeController.text;
                      Navigator.pop(context);
                    },
                    child: const Text(
                      "Apply",
                      style: TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showGitHubLinkDialog() {
    TextEditingController urlController = TextEditingController(text: _tempProjects[_currentIndex].githubUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add GitHub Link"),
        content: TextField(
          controller: urlController,
          decoration: const InputDecoration(hintText: "https://github.com/username/project_repo"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              _tempProjects[_currentIndex].githubUrl = urlController.text;
              Navigator.pop(context);
            },
            child: const Text("Save Git Link"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF000080),
        title: Text(
          "Project Blueprint Entry Box (${_currentIndex + 1}/${_tempProjects.length})",
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Container(
            width: screenWidth > 900 ? 900 : screenWidth * 0.95,
            color: Colors.white,
            child: Column(
              children: [
                _buildCustomBox("Project Name", _nameController, maxLines: 1, alignment: TextAlign.center),
                const SizedBox(height: 15),
                _buildCustomBox("Title", _titleController, maxLines: 2, alignment: TextAlign.center),
                const SizedBox(height: 20),
                screenWidth > 600
                    ? Row(
                  children: [
                    Expanded(child: _buildCustomBox("Challenges & Solutions\nProblem:\nSolution", _challengesController, maxLines: 6)),
                    const SizedBox(width: 20),
                    Expanded(child: _buildCustomBox("Key Features", _featuresController, maxLines: 6)),
                  ],
                )
                    : Column(
                  children: [
                    _buildCustomBox("Challenges & Solutions\nProblem:\nSolution", _challengesController, maxLines: 5),
                    const SizedBox(height: 15),
                    _buildCustomBox("Key Features", _featuresController, maxLines: 5),
                  ],
                ),
                const SizedBox(height: 25),

                screenWidth > 600
                    ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildTechHighlightSection(),
                    const Spacer(),
                    _buildProjectFormActions(),
                  ],
                )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTechHighlightSection(),
                    const SizedBox(height: 20),
                    _buildProjectFormActions(),
                  ],
                ),

// ================== Selected Images Preview ==================

                const SizedBox(height: 20),

                if (_tempProjects[_currentIndex].mediaFiles.isNotEmpty ||
                    _tempProjects[_currentIndex].mediaUrls.isNotEmpty) ...[

                  Text(
                    "Selected Images (${_tempProjects[_currentIndex].mediaFiles.length + _tempProjects[_currentIndex].mediaUrls.length})",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),

                  const SizedBox(height: 10),

                  SizedBox(
                    height: 110,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [

                        // ================= OLD SAVED IMAGES =================

                        ..._tempProjects[_currentIndex].mediaUrls.map((url) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    url,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 100,
                                        height: 100,
                                        color: Colors.grey.shade200,
                                        child: const Icon(
                                          Icons.broken_image,
                                          color: Colors.red,
                                          size: 40,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _tempProjects[_currentIndex]
                                            .mediaUrls
                                            .remove(url);
                                      });
                                    },
                                    child: const CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Colors.red,
                                      child: Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        // ================= NEW ADDED IMAGES =================

                        ..._tempProjects[_currentIndex]
                            .mediaFiles
                            .asMap()
                            .entries
                            .map((entry) {
                          final index = entry.key;
                          final image = entry.value;

                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    image,
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _tempProjects[_currentIndex]
                                            .mediaFiles
                                            .removeAt(index);
                                      });
                                    },
                                    child: const CircleAvatar(
                                      radius: 10,
                                      backgroundColor: Colors.red,
                                      child: Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 35),
                const Divider(),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildBlueprintButton("Save Setup", () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Uploading images & saving project...'),
                          duration: Duration(seconds: 2),
                        ),
                      );

                      await _saveProjectsToFirestore();
                      widget.onSave(_tempProjects);

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Project structure configuration updated!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        Navigator.pop(context);
                      }
                    }),

                    const SizedBox(width: 15),

                    _buildBlueprintButton("Delete Project", () {
                      if (_tempProjects.length > 1) {
                        setState(() {
                          _tempProjects.removeAt(_currentIndex);

                          if (_currentIndex >= _tempProjects.length) {
                            _currentIndex = _tempProjects.length - 1;
                          }

                          _initControllers();
                        });
                      }
                    }),

                    const SizedBox(width: 15),

                    _buildBlueprintButton("Add more", () {
                      _saveCurrentState();
                      setState(() {
                        _tempProjects.add(ProjectData());
                        _currentIndex = _tempProjects.length - 1;
                        _initControllers();
                      });
                    }),
                  ],
                ),
                if (_tempProjects.length > 1) ...[
                  const SizedBox(height: 25),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton(
                        onPressed: _currentIndex > 0
                            ? () {
                          _saveCurrentState();
                          setState(() {
                            _currentIndex--;
                            _initControllers();
                          });
                        }
                            : null,
                        child: const Text("Previous Project"),
                      ),
                      Text("Structure Block ${_currentIndex + 1} of ${_tempProjects.length}", style: const TextStyle(fontWeight: FontWeight.bold)),
                      ElevatedButton(
                        onPressed: _currentIndex < _tempProjects.length - 1
                            ? () {
                          _saveCurrentState();
                          setState(() {
                            _currentIndex++;
                            _initControllers();
                          });
                        }
                            : null,
                        child: const Text("Next Project"),
                      ),
                    ],
                  )
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTechHighlightSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Stack Highlighting", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(border: Border.all(color: Colors.blueAccent), borderRadius: BorderRadius.circular(8)),
          child: const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.bolt, color: Colors.blue, size: 18), Text(" Flutter ", style: TextStyle(fontWeight: FontWeight.bold))]),
              Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.code, color: Colors.cyan, size: 18), Text(" Dart ", style: TextStyle(fontWeight: FontWeight.bold))]),
              Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.local_fire_department, color: Colors.orange, size: 18), Text(" Firebase ", style: TextStyle(fontWeight: FontWeight.bold))]),
              Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.api, color: Colors.green, size: 18), Text(" REST APIs ", style: TextStyle(fontWeight: FontWeight.bold))]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProjectFormActions() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _buildBlueprintButton("View live demo", _pickLiveDemoMedia),
        _buildBlueprintButton("Add Drescribtion", _showCodeEditorDialog),
        _buildBlueprintButton("view on GitHub", _showGitHubLinkDialog),
      ],
    );
  }

  Widget _buildCustomBox(String hint, TextEditingController controller, {required int maxLines, TextAlign alignment = TextAlign.start}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF4A90E2), width: 1.5),
      ),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        textAlign: alignment,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w500),
          contentPadding: const EdgeInsets.all(15),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildBlueprintButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF4A90E2), width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

Future<String> uploadFileToStorage(Uint8List fileBytes, String fileName) async {
  try {
    return await uploadToCloudinary(
      fileBytes,
      fileName,
      folder: "portfolio/certificates",
    );
  } catch (e) {
    debugPrint("Upload error: $e");
    return "";
  }
}
void _showFullNetworkImageDialog(
    BuildContext context,
    String imageUrl,
    String name,
    ) {
  showDialog(
    context: context,
    builder: (context) {
      final screenSize = MediaQuery.of(context).size;

      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: screenSize.width * 0.90,
          height: screenSize.height * 0.85,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 8,
                  top: 8,
                  bottom: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5.0,
                    child: Center(
                      child: Image.network(
                        imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.broken_image,
                            size: 50,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
Future<String> uploadDashboardImage(Uint8List imageBytes) async {
  try {
    return await uploadToCloudinary(
      imageBytes,
      "dashboard_${DateTime.now().millisecondsSinceEpoch}.jpg",
      folder: "portfolio/dashboard",
    );
  } catch (e) {
    debugPrint("Dashboard Upload Error: $e");
    return "";
  }
}

Future<String?> uploadResumeToStorage(Uint8List pdfBytes, String fileName) async {
  try {
    final url = await uploadToCloudinary(
      pdfBytes,
      fileName,
      folder: "portfolio/resumes",
    );
    return url.isNotEmpty ? url : null;
  } catch (e) {
    debugPrint("PDF Upload error: $e");
    return null;
  }
}
class ExpertiseFormPage extends StatefulWidget {
  final List<ExpertiseSectionData> initialSections;
  final Function(List<ExpertiseSectionData>) onSave;

  const ExpertiseFormPage({super.key, required this.initialSections, required this.onSave});

  @override
  State<ExpertiseFormPage> createState() => _ExpertiseFormPageState();
}

class _ExpertiseFormPageState extends State<ExpertiseFormPage> {
  List<ExpertiseSectionData> _tempSections = [];
  int _currentSectionIndex = 0;
  late TextEditingController _sectionTitleController;
  bool _isLoading = true;
  // Expertise Summary Footer Controllers
  final TextEditingController _approachTitleController =
  TextEditingController(text: "My Approach");
  final TextEditingController _approachDescriptionController =
  TextEditingController(
    text:
    "I combine logistics domain knowledge with modern technology to create solutions that are efficient, scalable, and make a real impact in business.",
  );
  final TextEditingController _logisticsValueController =
  TextEditingController(text: "6+");
  final TextEditingController _logisticsLabelController =
  TextEditingController(
    text: "Years Experience in Logistics",
  );
  final TextEditingController _developmentValueController =
  TextEditingController(text: "3+");
  final TextEditingController _developmentLabelController =
  TextEditingController(
    text: "Years Experience in Development",
  );
  final TextEditingController _projectsValueController =
  TextEditingController(text: "20+");
  final TextEditingController _projectsLabelController =
  TextEditingController(
    text: "Projects Completed",
  );
  final TextEditingController _satisfactionValueController =
  TextEditingController(text: "100%");
  final TextEditingController _satisfactionLabelController =
  TextEditingController(
    text: "Client Satisfaction",
  );
  final TextEditingController _footerButtonTextController =
  TextEditingController(text: "View My Projects");
  @override
  void initState() {
    super.initState();
    _loadDataFromFirestore();
  }
  Future<void> _loadDataFromFirestore() async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('my_portfolio')
          .doc('user_data')
          .get();
      if (docSnapshot.exists && docSnapshot.data() != null) {
        final data = docSnapshot.data()!;
        if (data.containsKey('expertise')) {
          final List<dynamic> expertiseData = data['expertise'];
          _tempSections = expertiseData.map((sec) {
            return ExpertiseSectionData(
              sectionTitle: sec['sectionTitle'] ?? '',
              items: (sec['items'] as List<dynamic>).map((item) {
                return ExpertiseItemData(
                  title: item['title'] ?? '',
                  iconUrl: item['iconUrl'],
                  bulletPoints: List<String>.from(item['bulletPoints'] ?? []),
                  levelOrPercentage: item['levelOrPercentage'] ?? '',
                );
              }).toList(),
            );
          }).toList();
        }
        // Expertise Summary Footer Firestore from Load
        final dynamic footerRawData = data['expertiseFooter'];

        if (footerRawData is Map) {
          final Map<String, dynamic> footerData =
          Map<String, dynamic>.from(footerRawData);

          _approachTitleController.text =
              footerData['approachTitle']?.toString() ??
                  _approachTitleController.text;

          _approachDescriptionController.text =
              footerData['approachDescription']?.toString() ??
                  _approachDescriptionController.text;

          _logisticsValueController.text =
              footerData['logisticsValue']?.toString() ??
                  _logisticsValueController.text;

          _logisticsLabelController.text =
              footerData['logisticsLabel']?.toString() ??
                  _logisticsLabelController.text;

          _developmentValueController.text =
              footerData['developmentValue']?.toString() ??
                  _developmentValueController.text;

          _developmentLabelController.text =
              footerData['developmentLabel']?.toString() ??
                  _developmentLabelController.text;

          _projectsValueController.text =
              footerData['projectsValue']?.toString() ??
                  _projectsValueController.text;

          _projectsLabelController.text =
              footerData['projectsLabel']?.toString() ??
                  _projectsLabelController.text;

          _satisfactionValueController.text =
              footerData['satisfactionValue']?.toString() ??
                  _satisfactionValueController.text;

          _satisfactionLabelController.text =
              footerData['satisfactionLabel']?.toString() ??
                  _satisfactionLabelController.text;

          _footerButtonTextController.text =
              footerData['buttonText']?.toString() ??
                  _footerButtonTextController.text;
        }
      }

      if (_tempSections.isEmpty) {
        if (widget.initialSections.isNotEmpty) {
          for (var sec in widget.initialSections) {
            _tempSections.add(ExpertiseSectionData(
              sectionTitle: sec.sectionTitle,
              items: sec.items.map((item) => ExpertiseItemData(
                title: item.title,
                iconBytes: item.iconBytes,
                iconUrl: item.iconUrl,
                bulletPoints: List.from(item.bulletPoints),
                levelOrPercentage: item.levelOrPercentage,
              )).toList(),
            ));
          }
        } else {
          _tempSections.add(ExpertiseSectionData(
            sectionTitle: "LOGISTICS & OPERATIONS EXPERTISE",
            items: [
              ExpertiseItemData(
                title: "Supply Chain Management",
                bulletPoints: ["End-to-End Logistics", "Vendor Management"],
                levelOrPercentage: "Expert Level",
              )
            ],
          ));
        }
      }
    } catch (e) {
      print("Error loading expertise from Firestore: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _initControllers();
        widget.onSave(_tempSections);
      }
    }
  }
  void _initControllers() {
    if (_tempSections.isNotEmpty) {
      final currentSec = _tempSections[_currentSectionIndex];
      _sectionTitleController = TextEditingController(text: currentSec.sectionTitle);
    } else {
      _sectionTitleController = TextEditingController();
    }
  }

  void _saveCurrentState() {
    if (_tempSections.isNotEmpty) {
      _tempSections[_currentSectionIndex].sectionTitle = _sectionTitleController.text;
    }
  }

  Future<String?> uploadFileToStorage(Uint8List bytes, String fileName) async {
    try {
      final url = await uploadToCloudinary(
        bytes,
        fileName,
        folder: "portfolio/expertise_icons",
      );
      return url.isNotEmpty ? url : null;
    } catch (e) {
      debugPrint("Error uploading image: $e");
      return null;
    }
  }
  Future<void> _saveAllDataToFirestore() async {
    try {
      _saveCurrentState();

      final expertiseData = await Future.wait(_tempSections.map((sec) async {
        return {
          'sectionTitle': sec.sectionTitle,
          'items': await Future.wait(sec.items.map((item) async {
            String? iconUrl = item.iconUrl;
            if (item.iconBytes != null) {
              iconUrl = await uploadFileToStorage(item.iconBytes!, "expertise_icon_${DateTime.now().millisecondsSinceEpoch}.png");
            }
            return {
              'title': item.title,
              'iconUrl': iconUrl,
              'bulletPoints': item.bulletPoints,
              'levelOrPercentage': item.levelOrPercentage,
            };
          }).toList()),
        };
      }).toList());

      await FirebaseFirestore.instance
          .collection('my_portfolio')
          .doc('user_data')
          .set({
        'expertise': expertiseData,

        'expertiseFooter': {
          'approachTitle':
          _approachTitleController.text.trim(),

          'approachDescription':
          _approachDescriptionController.text.trim(),

          'logisticsValue':
          _logisticsValueController.text.trim(),

          'logisticsLabel':
          _logisticsLabelController.text.trim(),

          'developmentValue':
          _developmentValueController.text.trim(),

          'developmentLabel':
          _developmentLabelController.text.trim(),

          'projectsValue':
          _projectsValueController.text.trim(),

          'projectsLabel':
          _projectsLabelController.text.trim(),

          'satisfactionValue':
          _satisfactionValueController.text.trim(),

          'satisfactionLabel':
          _satisfactionLabelController.text.trim(),

          'buttonText':
          _footerButtonTextController.text.trim(),
        },
      }, SetOptions(merge: true));

      widget.onSave(_tempSections);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expertise data saved to Firestore!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print("Error saving expertise to Firestore: $e");
    }
  }
  Future<void> _pickItemIcon(ExpertiseItemData item) async {
    final ImagePicker picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        item.iconBytes = bytes;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    final currentSec = _tempSections[_currentSectionIndex];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFF000080),
        title: const Text(
          "Manage Expertise & Skills",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: screenWidth > 900 ? 900 : screenWidth * 0.95,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _currentSectionIndex > 0
                        ? TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _saveCurrentState();
                          _currentSectionIndex--;
                          _initControllers();
                        });
                      },
                      icon: const Icon(Icons.arrow_back_ios, size: 16, color: Color(0xFF000080)),
                      label: const Text(
                        "Previous",
                        style: TextStyle(color: Color(0xFF000080), fontWeight: FontWeight.bold),
                      ),
                    )
                        : const SizedBox.shrink(),
                    Text(
                      "Section ${_currentSectionIndex + 1} of ${_tempSections.length}",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF000080)),
                    ),
                    Row(
                      children: [
                        if (_currentSectionIndex < _tempSections.length - 1) ...[
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _saveCurrentState();
                                _currentSectionIndex++;
                                _initControllers();
                              });
                            },
                            label: const Text(
                              "Next",
                              style: TextStyle(color: Color(0xFF000080), fontWeight: FontWeight.bold),
                            ),
                            icon: const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF000080)),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Wrap(
                          spacing: 10,
                          children: [
                            ElevatedButton.icon(
                              onPressed: () {
                                _saveCurrentState();
                                setState(() {
                                  _tempSections.add(
                                    ExpertiseSectionData(
                                      sectionTitle: "NEW SECTION",
                                      items: [],
                                    ),
                                  );
                                  _currentSectionIndex = _tempSections.length - 1;
                                  _initControllers();
                                });
                              },
                              icon: const Icon(Icons.add),
                              label: const Text("Add Section"),
                            ),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                if (_tempSections.length <= 1) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("At least one section must remain."),
                                    ),
                                  );
                                  return;
                                }
                                _saveCurrentState();
                                setState(() {
                                  _tempSections.removeAt(_currentSectionIndex);
                                  if (_currentSectionIndex >= _tempSections.length) {
                                    _currentSectionIndex = _tempSections.length - 1;
                                  }
                                  _initControllers();
                                });
                              },
                              icon: const Icon(Icons.delete),
                              label: const Text("Delete Section"),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _sectionTitleController,
                  decoration: const InputDecoration(
                    labelText: "Section Title (e.g., LOGISTICS & OPERATIONS EXPERTISE)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                const Text("Expertise Cards / Items:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: currentSec.items.length,
                  itemBuilder: (context, itemIndex) {
                    final item = currentSec.items[itemIndex];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                InkWell(
                                  onTap: () => _pickItemIcon(item),
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade200,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.grey.shade400),
                                    ),
                                    child: item.iconBytes != null
                                        ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(item.iconBytes!, fit: BoxFit.cover))
                                        : (item.iconUrl != null && item.iconUrl!.isNotEmpty)
                                        ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(item.iconUrl!, fit: BoxFit.cover))
                                        : const Icon(Icons.add_a_photo, color: Colors.grey),
                                  ),
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: item.title,
                                    onChanged: (val) => item.title = val,
                                    decoration: const InputDecoration(labelText: "Card Title (e.g. Supply Chain Management)"),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              initialValue: item.levelOrPercentage,
                              onChanged: (val) => item.levelOrPercentage = val,
                              decoration: const InputDecoration(
                                labelText: "Level / Percentage (e.g. Expert Level or 95%)",
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              initialValue: item.bulletPoints.join('\n'),
                              onChanged: (val) {
                                setState(() {
                                  item.bulletPoints = val.split('\n').where((s) => s.trim().isNotEmpty).toList();
                                });
                              },
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: "Bullet Points (Write each point in a new line)",
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      currentSec.items.add(ExpertiseItemData(
                        title: '',
                        levelOrPercentage: '',
                        bulletPoints: [],
                      ));
                    });
                  },
                  icon: const Icon(Icons.add_circle),
                  label: const Text("Add New Card in this Section"),
                ),
                const SizedBox(height: 25),

                _buildFooterSettings(),

                const SizedBox(height: 40),

                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF000080),
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text("Save", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    onPressed: _saveAllDataToFirestore,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildFooterSettings() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isSmallScreen = constraints.maxWidth < 750;

        final double cardWidth = isSmallScreen
            ? constraints.maxWidth
            : (constraints.maxWidth - 16) / 2;

        InputDecoration fieldDecoration(
            String label,
            IconData icon,
            ) {
          return InputDecoration(
            labelText: label,
            prefixIcon: Icon(
              icon,
              color: const Color(0xFF000080),
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.grey.shade300,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF000080),
                width: 1.8,
              ),
            ),
          );
        }

        Widget metricCard({
          required IconData icon,
          required String title,
          required TextEditingController valueController,
          required TextEditingController labelController,
        }) {
          return SizedBox(
            width: cardWidth,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        color: const Color(0xFF000080),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF000080),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: valueController,
                    decoration: fieldDecoration(
                      "Value,  6+",
                      Icons.numbers,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: labelController,
                    decoration: fieldDecoration(
                      "Label",
                      Icons.title,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFF000080).withOpacity(0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 15,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.dashboard_customize_outlined,
                    color: Color(0xFF000080),
                    size: 28,
                  ),
                  SizedBox(width: 10),
                  Text(
                    "Expertise Summary Footer",
                    style: TextStyle(
                      color: Color(0xFF000080),
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                " Expertise window- summary footer",
                style: TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 22),

              TextField(
                controller: _approachTitleController,
                decoration: fieldDecoration(
                  "Approach Title",
                  Icons.person_outline,
                ),
              ),
              const SizedBox(height: 15),

              TextField(
                controller: _approachDescriptionController,
                maxLines: 4,
                decoration: fieldDecoration(
                  "Approach Description",
                  Icons.description_outlined,
                ),
              ),
              const SizedBox(height: 22),

              const Text(
                "Summary Statistics",
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 15),

              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  metricCard(
                    icon: Icons.business_center_outlined,
                    title: "Logistics Experience",
                    valueController:
                    _logisticsValueController,
                    labelController:
                    _logisticsLabelController,
                  ),
                  metricCard(
                    icon: Icons.code,
                    title: "Development Experience",
                    valueController:
                    _developmentValueController,
                    labelController:
                    _developmentLabelController,
                  ),
                  metricCard(
                    icon: Icons.folder_copy_outlined,
                    title: "Completed Projects",
                    valueController:
                    _projectsValueController,
                    labelController:
                    _projectsLabelController,
                  ),
                  metricCard(
                    icon: Icons.groups_outlined,
                    title: "Client Satisfaction",
                    valueController:
                    _satisfactionValueController,
                    labelController:
                    _satisfactionLabelController,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              TextField(
                controller: _footerButtonTextController,
                decoration: fieldDecoration(
                  "Button Text",
                  Icons.smart_button_outlined,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}