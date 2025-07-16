import 'package:flutter/material.dart';
import 'dart:ui';

/// Enhanced button with glow effect and animated states
class FuturisticGlowButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final IconData? icon;
  final String? label;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? glowColor;
  final bool showGlow;
  final double glowRadius;
  final double glowSpread;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final bool isToggled;
  final bool isLoading;
  final ButtonStyle? style;

  const FuturisticGlowButton({
    super.key,
    this.onPressed,
    required this.child,
    this.icon,
    this.label,
    this.backgroundColor,
    this.foregroundColor,
    this.glowColor,
    this.showGlow = true,
    this.glowRadius = 20.0,
    this.glowSpread = 2.0,
    this.padding,
    this.borderRadius,
    this.isToggled = false,
    this.isLoading = false,
    this.style,
  });

  @override
  State<FuturisticGlowButton> createState() => _FuturisticGlowButtonState();
}

class _FuturisticGlowButtonState extends State<FuturisticGlowButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _glowAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.02,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    
    if (widget.showGlow) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Dynamic colors based on toggle state (with increased transparency)
    final effectiveBackgroundColor = widget.isToggled 
        ? (widget.backgroundColor ?? theme.colorScheme.secondary).withOpacity(0.75)
        : (widget.backgroundColor ?? theme.colorScheme.primary).withOpacity(0.75);
    final effectiveForegroundColor = widget.isToggled 
        ? (widget.foregroundColor ?? theme.colorScheme.onSecondary)
        : (widget.foregroundColor ?? theme.colorScheme.onPrimary);
    final effectiveGlowColor = widget.glowColor ?? effectiveBackgroundColor;
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.showGlow ? _scaleAnimation.value : 1.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(24),
              boxShadow: widget.showGlow ? [
                BoxShadow(
                  color: effectiveGlowColor.withOpacity(0.25 * _glowAnimation.value),
                  blurRadius: widget.glowRadius * _glowAnimation.value,
                  spreadRadius: widget.glowSpread * _glowAnimation.value,
                  offset: const Offset(0, 2),
                ),
                BoxShadow(
                  color: effectiveGlowColor.withOpacity(0.12 * _glowAnimation.value),
                  blurRadius: widget.glowRadius * 1.5 * _glowAnimation.value,
                  spreadRadius: widget.glowSpread * 1.5 * _glowAnimation.value,
                  offset: const Offset(0, 4),
                ),
              ] : null,
            ),
            child: widget.icon != null && widget.label != null
                ? ElevatedButton.icon(
                    onPressed: widget.onPressed,
                    icon: widget.isLoading 
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                effectiveForegroundColor,
                              ),
                            ),
                          )
                        : Icon(widget.icon),
                    label: Text(widget.label!),
                    style: (widget.style ?? ElevatedButton.styleFrom()).copyWith(
                      backgroundColor: MaterialStateProperty.all(effectiveBackgroundColor),
                      foregroundColor: MaterialStateProperty.all(effectiveForegroundColor),
                      elevation: MaterialStateProperty.all(widget.showGlow ? 8 : 4),
                      shadowColor: MaterialStateProperty.all(effectiveGlowColor),
                      shape: MaterialStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: widget.borderRadius ?? BorderRadius.circular(24),
                        ),
                      ),
                      padding: MaterialStateProperty.all(
                        widget.padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  )
                : ElevatedButton(
                    onPressed: widget.onPressed,
                    style: (widget.style ?? ElevatedButton.styleFrom()).copyWith(
                      backgroundColor: MaterialStateProperty.all(effectiveBackgroundColor),
                      foregroundColor: MaterialStateProperty.all(effectiveForegroundColor),
                      elevation: MaterialStateProperty.all(widget.showGlow ? 8 : 4),
                      shadowColor: MaterialStateProperty.all(effectiveGlowColor),
                      shape: MaterialStateProperty.all(
                        RoundedRectangleBorder(
                          borderRadius: widget.borderRadius ?? BorderRadius.circular(24),
                        ),
                      ),
                      padding: MaterialStateProperty.all(
                        widget.padding ?? const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                    child: widget.child,
                  ),
          ),
        );
      },
    );
  }
}

/// Enhanced secondary button with better dark mode contrast
class FuturisticSecondaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final IconData? icon;
  final String? label;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final bool isLoading;

  const FuturisticSecondaryButton({
    super.key,
    this.onPressed,
    required this.child,
    this.icon,
    this.label,
    this.padding,
    this.borderRadius,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Better contrast colors for dark mode (with increased transparency)
    final backgroundColor = isDark 
        ? theme.colorScheme.surface.withOpacity(0.6)
        : theme.colorScheme.secondary.withOpacity(0.7);
    final foregroundColor = isDark 
        ? theme.colorScheme.primary
        : theme.colorScheme.onSecondary;
    final borderColor = isDark 
        ? theme.colorScheme.primary.withOpacity(0.4)
        : theme.colorScheme.secondary.withOpacity(0.25);
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius ?? BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(isDark ? 0.2 : 0.12),
            blurRadius: 12,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: borderRadius ?? BorderRadius.circular(24),
              border: Border.all(
                color: borderColor,
                width: 1.5,
              ),
            ),
            child: icon != null && label != null
                ? ElevatedButton.icon(
                    onPressed: onPressed,
                    icon: isLoading 
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                            ),
                          )
                        : Icon(icon),
                    label: Text(label!),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: foregroundColor,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: borderRadius ?? BorderRadius.circular(24),
                      ),
                      padding: padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  )
                : ElevatedButton(
                    onPressed: onPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: foregroundColor,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: borderRadius ?? BorderRadius.circular(24),
                      ),
                      padding: padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: child,
                  ),
          ),
        ),
      ),
    );
  }
}
