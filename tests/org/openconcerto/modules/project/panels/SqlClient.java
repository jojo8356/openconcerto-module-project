package org.openconcerto.modules.project.panels;

import java.util.List;
import java.util.Map;

/**
 * Acces a PostgreSQL pour la suite de tests « panneaux ».
 *
 * <p>
 * Deux implementations : JDBC (si le pilote PostgreSQL est dans le classpath)
 * ou appel du binaire <code>psql</code>. La seconde permet de faire tourner
 * la suite avec un simple JDK et postgresql-client, sans JAR supplementaire.
 * </p>
 *
 * <p>
 * Toutes les requetes envoyees par la suite sont des SELECT : la base n'est
 * jamais modifiee.
 * </p>
 */
public interface SqlClient {

    /**
     * Execute une requete et renvoie les lignes, colonne par colonne. Les
     * valeurs NULL sont representees par <code>null</code>, les autres par
     * leur representation textuelle.
     */
    List<Map<String, Object>> query(String sql) throws Exception;

    /** Execute une requete sans se soucier du resultat. */
    void execute(String sql) throws Exception;

    /** Libere les ressources. */
    void close();

    /** Description du transport utilise (pour le rapport). */
    String describe();
}
