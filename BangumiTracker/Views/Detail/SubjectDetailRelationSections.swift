import SwiftUI

// MARK: - Characters

struct CharactersSection: View {
    let characters: [SubjectCharacter]

    var body: some View {
        DetailSectionCard(spacing: 12) {
            Text("角色 / 声优")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(characters.prefix(10)) { character in
                NavigationLink(value: AppRoute.characterDetail(id: character.id)) {
                    CharacterRow(character: character)
                }
                .buttonStyle(.plain)
            }

            if characters.count > 10 {
                Text("共 \(characters.count) 个角色")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
    }
}

struct CharacterRow: View {
    let character: SubjectCharacter

    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(
                urlString: character.images?.imageURL,
                fallbackText: character.displayName,
                targetSize: CGSize(width: 36, height: 36)
            )
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(character.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundColor(.primary)
                    if !character.roleText.isEmpty {
                        Text(character.roleText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                if let actor = character.actors?.first {
                    Text("CV: \(actor.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Persons

struct PersonsSection: View {
    let persons: [SubjectPerson]

    var body: some View {
        DetailSectionCard(spacing: 12) {
            Text("制作人员")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(persons.prefix(10)) { person in
                NavigationLink(value: AppRoute.personDetail(id: person.id)) {
                    PersonRow(person: person)
                }
                .buttonStyle(.plain)
            }

            if persons.count > 10 {
                Text("共 \(persons.count) 位制作人员")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
    }
}

struct PersonRow: View {
    let person: SubjectPerson

    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(
                urlString: person.images?.imageURL,
                fallbackText: person.displayName,
                targetSize: CGSize(width: 36, height: 36)
            )
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(person.displayName)
                        .font(.callout.weight(.medium))
                        .foregroundColor(.primary)
                    if let position = person.position, !position.isEmpty {
                        Text(position)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Related Subjects

struct RelatedSection: View {
    let relatedSubjects: [RelatedSubject]

    var body: some View {
        DetailSectionCard(spacing: 10) {
            Text("相关作品")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            ForEach(relatedSubjects) { related in
                NavigationLink(value: AppRoute.subjectDetail(id: related.id)) {
                    RelatedSubjectRow(related: related)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct RelatedSubjectRow: View {
    let related: RelatedSubject

    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(
                urlString: related.imageURL,
                fallbackText: related.displayName,
                targetSize: CGSize(width: 36, height: 50)
            )
                .frame(width: 36, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 1) {
                Text(related.displayName)
                    .font(.callout.weight(.medium))
                    .foregroundColor(.primary)
                if let relation = related.relation, !relation.isEmpty {
                    Text(relation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }
}
