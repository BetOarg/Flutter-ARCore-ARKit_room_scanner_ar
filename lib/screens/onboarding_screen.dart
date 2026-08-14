import 'package:flutter/material.dart';

import '../services/onboarding_service.dart';

/// Contenido estático de cada slide de la introducción.
class _OnboardingSlide {
  final IconData icon;
  final String title;
  final String description;

  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
  });
}

const _slides = <_OnboardingSlide>[
  _OnboardingSlide(
    icon: Icons.architecture_rounded,
    title: 'Medí tus ambientes sin cinta métrica',
    description:
        'Escaneá con la cámara o cargá las medidas a mano — vos elegís cómo.',
  ),
  _OnboardingSlide(
    icon: Icons.compare_arrows_rounded,
    title: 'Con AR o sin AR, como prefieras',
    description:
        'Con AR: apuntá la cámara y las paredes se detectan solas.\n'
        'Sin AR: dibujá el contorno y anotá las medidas con tu cinta métrica.',
  ),
  _OnboardingSlide(
    icon: Icons.picture_as_pdf_outlined,
    title: 'Un plano 2D listo para compartir',
    description:
        'Al terminar, exportá el plano a PDF para compartirlo o guardá un '
        'respaldo en JSON.',
  ),
];

/// Introducción de tres pantallas, mostrada una única vez antes del login.
///
/// Se muestra antes de pedir inicio de sesión a propósito: el usuario
/// necesita entender qué hace la app — y que existen dos modos de captura,
/// AR y manual — antes de que la app le pida una decisión sobre eso. Sin
/// esta introducción, el selector de modo ([CaptureModeScreen]) sería la
/// primera vez que el usuario se entera de que existe una alternativa sin
/// cámara, justo en el peor momento para explicarlo.
class OnboardingScreen extends StatefulWidget {
  /// Se invoca una vez que el usuario termina u omite la introducción.
  final VoidCallback onFinish;

  const OnboardingScreen({super.key, required this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;
  bool _finishing = false;

  Future<void> _finish() async {
    if (_finishing) return; // evita doble-tap mientras se persiste el flag
    setState(() => _finishing = true);

    await OnboardingService.markOnboardingSeen();
    if (!mounted) return;

    widget.onFinish();
  }

  void _goToNextPage() {
    if (_currentPage == _slides.length - 1) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                child: TextButton(
                  onPressed: _finishing ? null : _finish,
                  child: const Text('Omitir'),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) => _SlideView(slide: _slides[index]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (index) {
                final isActive = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _finishing ? null : _goToNextPage,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _finishing
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isLastPage ? 'Empezar' : 'Siguiente'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _OnboardingSlide slide;

  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(slide.icon, size: 96, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 32),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            slide.description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
