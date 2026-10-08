/// The school's own configurable identity — set once via the first-launch
/// setup assistant (or carried over automatically from the built-in
/// defaults for an installation that existed before it). Null name/box/phone
/// mean "use the built-in defaults" (see [ReceiptLabels.forSection]).
class SchoolIdentity {
  final String? name;
  final String? box;
  final String? phone;
  final String matriculePrefix;

  const SchoolIdentity({
    this.name,
    this.box,
    this.phone,
    required this.matriculePrefix,
  });
}
